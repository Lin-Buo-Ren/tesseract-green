#!/usr/bin/env bash
# Detect and collect all native programs' straight forward library dependencies to a directory for portable distribution
# 林博仁(Buo-ren, Lin) <Buo.Ren.Lin@gmail.com>

# 於任何命令失敗（結束狀態非零）時中止腳本運行
# 流水線(pipeline)中的任何組成命令失敗視為整條流水線失敗
set \
    -o errexit \
    -o errtrace \
    -o pipefail

# 方便給別人改的變數宣告放在這裡，變數名稱建議大寫英文與底線
#API_TOKEN=0123456789ABCDEF
#USERNAME=root

# 腳本運行的主要邏輯寫在這裡
main(){
    # 便利變數，不使用可移除
    # script_basecommand：執行腳本的基底命令，例如： ./script.sh
    # script_dir：腳本所在的目錄路徑
    # script_filename：腳本檔案名（含副檔名），例如 script.sh
    # script_name：腳本名稱（不含副檔名），例如 script
    # script_args：執行腳本的命令列參數的陣列，使用 "${script_args[0]}" 存取

    # shellcheck disable=SC2034
    script_basecommand="${1}"; shift 1
    # shellcheck disable=SC2034
    script_dir="$(
       dirname "$(
           realpath \
               --strip \
               "${BASH_SOURCE[0]}"
       )"
    )"
    # shellcheck disable=SC2034
    script_filename="${BASH_SOURCE##*/}"
    # shellcheck disable=SC2034
    script_name="${script_filename%%.*}"
    # shellcheck disable=SC2034
    script_args=("${@}")

    # ↓↓↓從這裡開始寫↓↓↓
    if test "${#script_args[@]}" != 2; then
        print_help \
            "${script_basecommand}"
        exit 1
    fi

    native_program_rootdir="${script_args[0]}"; shift_array script_args
    common_libdir="${script_args[0]}"; shift_array script_args

    if ! test -d "${native_program_rootdir}"; then
        printf -- \
            'Error: %s does not exist or is not a directory\n' \
            "${native_program_rootdir}" \
            1>&2
        exit 1
    fi

    if ! test -d "${common_libdir}"; then
        printf -- \
            'Error: %s does not exist or is not a directory\n' \
            "${common_libdir}" \
            1>&2
        exit 1
    fi

    while IFS= read -r -d $'\0' file_under_test; do
        # ldd(1) returns non-zero if the file isn't a dynamically linked native
        # program
        if ldd "${file_under_test}" &>/dev/null; then
            determine_and_copy_library_file_of_a_native_program_to_libdir \
                "${file_under_test}" \
                "${common_libdir}"
        fi
    done < <(
        # Since Unix native program files have no filename extension pattern, we
        # check all of the regular files
        find "${native_program_rootdir}" \
            -type f \
            -print0
    )

    exit 0
}

# 將原生程式所依賴的程式庫檔案複製到新的程式庫目錄
determine_and_copy_library_file_of_a_native_program_to_libdir(){
    # The native program file(i.e. not a script) to check for library dependencies
    declare native_program_file="${1}"; shift
    # The common library directory to copy the depending libraries to
    declare common_libdir="${1}"; shift

    # Check depending libraries, parse the paths out(with some blacklisted
    # libraries stripped out due to incompatibilities), then copy them to the
    # common library directory if it isn't done already
    ldd "${native_program_file}" \
        | (
            grep \
                --extended-regexp \
                --only-matching \
                '/[[:graph:]]+' \
                || test "${?}" == 1
        ) | (
            grep \
                --extended-regexp \
                --invert-match \
                '/(ld-linux.*|libc|libdl|libgcc_s|libm|libstdc\+\+|linux-vdso|libpthread)\.so.*' \
                || test "${?}" == 1
        ) | xargs \
            --no-run-if-empty \
            --replace={} \
            --verbose \
            -- \
            cp \
                --no-clobber \
                {} \
                "${common_libdir}"
}

## 檢查腳本運行時期依賴的命令是否存在
check_runtime_dependencies(){
    local \
        failed=false

    for required_command in \
        basename \
        dirname \
        grep \
        ldd \
        realpath \
        xargs; do
        if ! command -v "${required_command}" &>/dev/null; then
            failed=true

            printf -- \
                'Error: This script requires the %s command to be available in the command search PATHs.\n\n' \
                "${required_command}" \
                1>&2
        fi
    done

    if test "${failed}" == true; then
        return 1
    else
        return 0
    fi
}

# 印出腳本使用幫助訊息的函式
print_help(){
    local script_basecommand="${1}"

    printf \
        'Usage: %s _native_program_rootdir_ _common_lib_dir_\n' \
        "${script_basecommand}"
}

# Simulate shift(builtin), but for bash indexed arrays
shift_array(){
    # array_ref: Name reference to an array
    # count: How many array elements to shift
    case "${#}" in
        1)
            declare -n array_ref="${1}"; shift 1
            declare -i count=1
        ;;
        2)
            declare -n array_ref="${1}"; shift 1
            declare -i count="${1}"; shift 1
        ;;
        *)
            printf -- \
                '%s: Fatal: This function requires 1 or 2 arguments.\n' \
                "${FUNCNAME[0]}" \
                1>&2
            exit 1
        ;;
    esac

    # NOTE: until(buitin): Do stuff when statement test fails
    until test "${count}" -eq 0; do
        if test "${#array_ref[@]}" = 0; then
            return 1
        else
            unset 'array_ref[0]'
            array_ref=("${array_ref[@]}")
        fi
        (( count -= 1 )) || true
    done
    return 0
}

# ERR情境所觸發的陷阱函式，用來進行腳本錯誤退出的後續處裡
trap_err(){
    printf \
        '\nScript prematurely aborted at line %s of the %s function with the %s exit status.\n' \
        "${BASH_LINENO[0]}" \
        "${FUNCNAME[1]}" \
        "${?}" \
        1>&2
}
trap trap_err ERR

# EXIT情境所觸發的陷阱函式，用來進行腳本結束前的處理
# 包含但不限於清理暫時檔案等
#trap_exit(){
#    cleanup_temp_files
#}
#trap trap_exit EXIT

check_runtime_dependencies

main "${0}" "${@}"
