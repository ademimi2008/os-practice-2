
from pathlib import Path

file_path = Path("sample.txt")

try:
    content = file_path.read_bytes()
    print(f"File: {file_path}")
    print(f"Size: {len(content)} bytes")
except OSError as error:
    print(f"Error: {error}")
    raise SystemExit(1)
