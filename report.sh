
#!/usr/bin/env bash

usage() {
    echo "Usage: $0 <directory> <ERROR|WARN> [--top N]"
}

if [[ $# -lt 2 ]]; then
    usage
    exit 1
fi

directory=$1
level=$2
top=""

if [[ ! -d "$directory" ]]; then
    echo "Error: directory does not exist: $directory" >&2
    exit 1
fi

if [[ "$level" != "ERROR" && "$level" != "WARN" ]]; then
    echo "Error: level must be ERROR or WARN" >&2
    usage
    exit 1
fi

if [[ $# -gt 2 ]]; then
    if [[ $# -ne 4 || "$3" != "--top" || ! "$4" =~ ^[1-9][0-9]*$ ]]; then
        usage
        exit 1
    fi
    top=$4
fi

awk -v level="$level" '
{
    for (i = 1; i <= NF; i++) {
        if ($i == level && i < NF) {
            module = $(i + 1)
            if (module != "") count[module]++
            break
        }
    }
}
END {
    for (module in count) {
        printf "%s %d\n", module, count[module]
    }
}' "$directory"/*.log 2>/dev/null |
sort -k2,2nr -k1,1 |
{
    if [[ -n "$top" ]]; then
        head -n "$top"
    else
        cat
    fi
} |
{
    printf "%-22s %s\n" "Module" "Count"
    printf "%-22s %s\n" "---------------------" "-----"
    awk '{printf "%-22s %s\n", $1, $2}'
}
