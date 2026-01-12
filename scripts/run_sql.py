import duckdb
import sys
from pathlib import Path

def split_sql(script: str):
    """
    Split SQL script into statements by semicolon, but do NOT split inside
    single quotes, double quotes, or dollar-quoted strings (basic).
    """
    statements = []
    buf = []
    in_single = False
    in_double = False
    i = 0
    while i < len(script):
        ch = script[i]

        # toggle single quotes (')
        if ch == "'" and not in_double:
            # handle escaped ''
            if in_single and i + 1 < len(script) and script[i + 1] == "'":
                buf.append(ch)
                buf.append(script[i + 1])
                i += 2
                continue
            in_single = not in_single
            buf.append(ch)
            i += 1
            continue

        # toggle double quotes (")
        if ch == '"' and not in_single:
            in_double = not in_double
            buf.append(ch)
            i += 1
            continue

        # statement end
        if ch == ";" and not in_single and not in_double:
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    last = "".join(buf).strip()
    if last:
        statements.append(last)
    return statements

def is_select(stmt: str) -> bool:
    # remove leading comment lines
    lines = []
    for line in stmt.splitlines():
        if line.strip().startswith("--") or line.strip() == "":
            continue
        lines.append(line)
    s = ("\n".join(lines)).strip().lower()
    return s.startswith("select") or s.startswith("with")


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/run_sql.py sql/01_event_validation.sql")
        raise SystemExit(1)

    sql_file = Path(sys.argv[1])
    if not sql_file.exists():
        raise FileNotFoundError(sql_file)

    sql_text = sql_file.read_text(encoding="utf-8")
    stmts = split_sql(sql_text)

    con = duckdb.connect(database=":memory:")

    print(f"▶ Running: {sql_file} (statements: {len(stmts)})\n")

    for idx, stmt in enumerate(stmts, start=1):
        # skip pure comment blocks
        if not stmt.strip():
            continue

        try:
            if is_select(stmt):
                df = con.execute(stmt).fetchdf()
                print(f"--- RESULT {idx} (rows={len(df)}) ---")
                if len(df) == 0:
                    print("Empty result\n")
                else:
                    print(df.head(50).to_string(index=False))
                    print()
            else:
                con.execute(stmt)
        except Exception as e:
            print(f"\n❌ Error in statement {idx}:\n{stmt}\n")
            raise

if __name__ == "__main__":
    main()
