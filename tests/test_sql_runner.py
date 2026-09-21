"""Check file decoding and failure cleanup without connecting to Snowflake."""
from io import StringIO
from unittest.mock import MagicMock

import pytest
from snowflake.connector.util_text import split_statements

from src.warehouse import run_sql_file as runner


@pytest.mark.parametrize("bom", [b"", b"\xef\xbb\xbf"])
def test_runner_accepts_both_utf8_forms(tmp_path, monkeypatch, bom):
    sql_file = tmp_path / "check.sql"
    sql_file.write_bytes(bom + b"-- comment\nSELECT 'a;b';")
    conn = MagicMock()
    cursor = MagicMock()
    cursor.description = [("value",)]
    cursor.fetchmany.return_value = [("a;b",)]
    def execute(stream, remove_comments):
        statements = list(split_statements(StringIO(stream.read()), remove_comments=remove_comments))
        assert len(statements) == 1
        assert statements[0][0].strip() == "SELECT 'a;b';"
        yield cursor
    conn.execute_stream.side_effect = execute
    monkeypatch.setattr(runner, "get_snowflake_connection", lambda: conn)
    monkeypatch.setattr("sys.argv", ["runner", str(sql_file)])
    assert runner.main() == 0
    cursor.fetchmany.assert_called_once_with(21)
    cursor.close.assert_called_once()
    conn.close.assert_called_once()
    # The file owns its transaction boundary; the runner must not commit an
    # incomplete manual transaction just because it reached the end of a file.
    conn.commit.assert_not_called()


def test_sql_failure_rolls_back_and_closes(tmp_path, monkeypatch):
    sql_file = tmp_path / "bad.sql"
    sql_file.write_text("SELECT invalid;", encoding="utf-8")
    conn = MagicMock()
    conn.execute_stream.side_effect = RuntimeError("SQL failed")
    monkeypatch.setattr(runner, "get_snowflake_connection", lambda: conn)
    monkeypatch.setattr("sys.argv", ["runner", str(sql_file)])
    assert runner.main() == 1
    conn.rollback.assert_called_once()
    conn.close.assert_called_once()
