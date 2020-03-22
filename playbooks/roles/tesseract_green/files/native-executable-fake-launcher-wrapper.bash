#!/usr/bin/env bash
# A wrapper to run specified native executable program with custom dynamic linker configuration
# Rename the native executable to _filename_.real, and create a _filename_ symbolic link targeting this script to make it work
# 林博仁(Buo-ren, Lin) <Buo.Ren.Lin@gmail.com>

set \
    -o errexit \
    -o errtrace \
    -o pipefail \
    -o nounset

init(){
    local script_basecommand="${1}"; shift
    local -a cmdline_args
    # COMPAT: 避免 Bash <= 4.3 於無命令列參數下展開 $@ 會觸發 nounset 檢查的問題
    if test "${#}" -ne 0; then
        cmdline_args=("${@}")
    else
        cmdline_args=()
    fi

    local installation_prefix_dir="${script_dir%/*}"

    local main_library_dir="${installation_prefix_dir}"/lib

    local real_executable="${script_basecommand}".real

    local dependencies_dir="${installation_prefix_dir}"/dependencies

    if ! check_runtime_parameters \
            "${real_executable}" \
            "${dependencies_dir}"; then
        printf -- \
            'Error: Runtime parameters invalid, check your installation.\n' \
            1>&2
            exit 1
    fi

    # Collect and set proper runtime library paths
    local -a ld_library_paths=()
    local possible_lib_dir
    for dependency_dir in "${dependencies_dir}"/*; do
        # Skip regular files in dependencies directory
        if ! test -d "${dependency_dir}"; then
            continue
        fi

        for possible_lib_dir_name in lib lib64 lib/x86_64-linux-gnu; do
            possible_lib_dir="${dependency_dir}"/"${possible_lib_dir_name}"
            if test -d "${possible_lib_dir}"; then
                ld_library_paths+=("${possible_lib_dir}")
            fi
        done
    done


    export LD_LIBRARY_PATH=
    for ld_library_path in "${ld_library_paths[@]}"; do
        if test -z "${LD_LIBRARY_PATH}"; then
            # Environment variable is empty, no separator is required
            LD_LIBRARY_PATH="${ld_library_path}"
        else
            # Add separator and append new path
            LD_LIBRARY_PATH="${LD_LIBRARY_PATH}":"${ld_library_path}"
        fi
    done

    # add main library path as well
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH}":"${main_library_dir}"

    # For debugging linking issues
    if test -v LAUNCHER_DEBUG_LDD; then
        exec ldd "${real_executable}"
    fi

    # COMPAT: 避免 Bash <= 4.3 於無命令列參數下展開 $@ 會觸發 nounset 檢查的問題
    if test "${#cmdline_args[@]}" = 0; then
        exec "${real_executable}"
    else
        exec "${real_executable}" "${cmdline_args[@]}"
    fi

    exit 0
}

# Check whether the runtime parameters are proper and return sane error message
# when it's not
check_runtime_parameters(){
    local real_executable="${1}"; shift
    local dependencies_dir="${1}"; shift

    if ! test -e "${real_executable}" \
        || ! test -x "${real_executable}"; then
        printf -- \
            '%s: Error: "%s" does not exist or is not an executable.\n' \
            "${FUNCNAME[0]}" \
            "${real_executable}" \
            1>&2
        return 1
    fi

    if ! test -e "${dependencies_dir}" \
        || ! test -d "${dependencies_dir}"; then
        printf -- \
            '%s: Error: "%s" does not exist or is not a directory.\n' \
            "${FUNCNAME[0]}" \
            "${dependencies_dir}" \
            1>&2
        return 1
    fi
}

# Check whether the dependency of the script are met
check_runtime_dependencies(){
    local \
        failed=false

    for required_command in \
        basename \
        dirname \
        realpath; do
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
if ! check_runtime_dependencies; then
    printf -- \
        'Error: Runtime dependencies not satisfied, check the installation.\n' \
        1>&2
    exit 1
fi

# 便利變數
# script_basecommand：執行腳本的基底命令，例如： ./script.sh
# script_dir：腳本所在的目錄路徑
# script_filename：腳本檔案名（含副檔名），例如 script.sh
# script_name：腳本名稱（不含副檔名），例如 script
# shellcheck disable=SC2034
{
    script_basecommand="${0}"
    script_dir="${BASH_SOURCE[0]%/*}"
    script_filename="${BASH_SOURCE[0]##*/}"
    script_name="${script_filename%%.*}"
}

trap_err(){
    printf \
        '\nScript prematurely aborted at line %s of the %s function with the exit status %u.\n' \
        "${BASH_LINENO[0]}" \
        "${FUNCNAME[1]}" \
        "${?}" \
        1>&2
}
trap trap_err ERR

# COMPAT: 避免 Bash <= 4.3 於無命令列參數下展開 $@ 會觸發 nounset 檢查的問題
if test "${#}" -eq 0; then
    init "${script_basecommand}"
else
    init "${script_basecommand}" "${@}"
fi
