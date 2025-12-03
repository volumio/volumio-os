#!/usr/bin/env bash
# set -e pipefail

# Make life simpler
cd "$GITHUB_WORKSPACE" || exit 1

# Fix for Git 2.35.2+ dubious ownership check in Docker containers
git config --global --add safe.directory "$GITHUB_WORKSPACE"

# Grep for shebang to account for scripts that don't have extensions
# grep -Eq '^#!(.*/|.*env +)(sh|bash|ksh)'

if [[ "${INPUT_ONLY_CHANGED}" == true ]]; then
	# Check only files changed in this commit(s)/merge
	if [[ -n "${GITHUB_BASE_REF}" ]]; then
		echo "Getting file history: PR"
		git fetch origin "${GITHUB_BASE_REF}" --depth=1
		REF_FROM_TO=("origin/${GITHUB_BASE_REF}" "${GITHUB_SHA}")
	elif [[ -n "${GITHUB_BEFORE_SHA}" && "${GITHUB_BEFORE_SHA}" != "0000000000000000000000000000000000000000" ]]; then
		echo "Getting file history: push ${GITHUB_BEFORE_SHA}"
		git fetch origin "${GITHUB_BEFORE_SHA}" --depth=1
		REF_FROM_TO=("${GITHUB_BEFORE_SHA}" "${GITHUB_SHA}")
	else
		echo "No valid reference for diff - checking all files with shebang"
		INPUT_ONLY_CHANGED=false
	fi

	if [[ "${INPUT_ONLY_CHANGED}" == true ]]; then
		[[ -n ${INPUT_PATTERN} ]] &&
			readarray -td '' FILES < <(git diff --name-only "${REF_FROM_TO[@]}" -z -- "${INPUT_PATTERN}")
		readarray -td '' FILES < <(git diff --name-only "${REF_FROM_TO[@]}" -z | xargs -0 grep -ElZ '^#!(.*/|.*env +)(sh|bash|ksh)' 2>/dev/null || true)
	fi
fi

if [[ "${INPUT_ONLY_CHANGED}" != true ]]; then
	[[ -n ${INPUT_PATTERN} ]] &&
		readarray -td '' FILES < <(find "${INPUT_PATH}" -not -path "${INPUT_EXCLUDE}" -type f -name "${INPUT_PATTERN}" -print0)
	readarray -td '' FILES < <(
		find "${INPUT_PATH}" -not -path "${INPUT_EXCLUDE}" -type f -exec grep -lZ '^#!.*\(bash\|sh\|ksh\)' {} \; 2>/dev/null || true
	)
fi

if [[ ${#FILES[@]} -gt 0 ]]; then
	echo "Checking and formatting ${#FILES[@]} files -- ${FILES[*]}"
	echo -e "\nRunning static analysis"
	# shellcheck disable=SC2086
	shellcheck ${INPUT_SHELLCHECK_FLAGS} "${FILES[@]}"
	sc_exit=$?

	echo -e "\nRunning formatting check"
	# shellcheck disable=SC2086
	shfmt ${INPUT_SHFMT_FLAGS} "${FILES[@]}"
	sh_exit=$?

	echo "shellcheck ${sc_exit}, shfmt ${sh_exit}"
	[ $sc_exit -ne 0 ] || [ $sh_exit -ne 0 ] && exit 1

	echo "All checks passed"
	exit 0
else
	echo "No files to check"
	exit 0
fi
