#!/bin/bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
[[ -z ${DEVTOOLS_INCLUDE_VERSION_UPGRADE_SH:-} ]] || return 0
DEVTOOLS_INCLUDE_VERSION_UPGRADE_SH=1

_DEVTOOLS_LIBRARY_DIR=${_DEVTOOLS_LIBRARY_DIR:-@pkgdatadir@}
# shellcheck source=src/lib/common.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/common.sh
# shellcheck source=src/lib/version/check.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/version/check.sh
# shellcheck source=src/lib/util/pkgbuild.sh
source "${_DEVTOOLS_LIBRARY_DIR}"/lib/util/pkgbuild.sh

source /usr/share/makepkg/util/message.sh

set -e

pkgctl_version_upgrade_usage() {
	local -r COMMAND=${_DEVTOOLS_COMMAND:-${BASH_SOURCE[0]##*/}}
	cat <<- _EOF_
		Usage: ${COMMAND} [OPTIONS] [PKGBASE]...

		Upgrade the PKGBUILD according to the latest available upstream version

		Uses nvchecker, a .nvchecker.toml file and the current PKGBUILD
		pkgver to check if there is a newer package version available.

		The current working directory is used if no PKGBASE is specified.

		OPTIONS
		    -h, --help          Show this help text

		EXAMPLES
		    $ ${COMMAND} neovim vim
_EOF_
}

pkgctl_version_upgrade() {
	local path upstream_version result
	local pkgbases=()
	local exit_code=0

	while (( $# )); do
		case $1 in
			-h|--help)
				pkgctl_version_upgrade_usage
				exit 0
				;;
			--)
				shift
				break
				;;
			-*)
				die "invalid argument: %s" "$1"
				;;
			*)
				pkgbases=("$@")
				break
				;;
		esac
	done

	if ! command -v nvchecker &>/dev/null; then
		die "The \"$_DEVTOOLS_COMMAND\" command requires 'nvchecker'"
	fi

	# Check if used without pkgbases in a packaging directory
	if (( ${#pkgbases[@]} == 0 )); then
		if [[ -f PKGBUILD ]]; then
			pkgbases=(".")
		else
			pkgctl_version_upgrade_usage
			exit 1
		fi
	fi

	for path in "${pkgbases[@]}"; do
		pushd "${path}" >/dev/null

		if [[ ! -f "PKGBUILD" ]]; then
			die "No PKGBUILD found for ${path}"
		fi

		# reset common PKGBUILD variables
		unset pkgbase pkgname arch source pkgver pkgrel validpgpkeys
		# shellcheck source=contrib/makepkg/PKGBUILD.proto
		. ./PKGBUILD
		pkgbase=${pkgbase:-$pkgname}

		if ! result=$(get_upstream_version); then
			result="${BOLD}${pkgbase}${ALL_OFF}: ${result}"
			failure+=("${result}")
			popd >/dev/null
			continue
		fi
		upstream_version=${result}

		if ! result=$(vercmp "${upstream_version}" "${pkgver}"); then
			result="${BOLD}${pkgbase}${ALL_OFF}: failed to compare version ${upstream_version} against ${pkgver}"
			failure+=("${result}")
			popd >/dev/null
			continue
		fi

		if (( result == 0 )); then
			result="${BOLD}${pkgbase}${ALL_OFF}: current version ${PURPLE}${pkgver}${ALL_OFF} is latest"
			up_to_date+=("${result}")
		elif (( result < 0 )); then
			result="${BOLD}${pkgbase}${ALL_OFF}: current version ${PURPLE}${pkgver}${ALL_OFF} is never than ${DARK_GREEN}${upstream_version}${ALL_OFF}"
			up_to_date+=("${result}")
		elif (( result > 0 )); then
			result="${BOLD}${pkgbase}${ALL_OFF}: upgraded from version ${PURPLE}${pkgver}${ALL_OFF} to ${DARK_GREEN}${upstream_version}${ALL_OFF}"
			out_of_date+=("${result}")

			# change the PKGBUILD
			pkgbuild_set_pkgver "${upstream_version}"
			pkgbuild_set_pkgrel 1
		fi

		popd >/dev/null
	done

	if (( ${#failure[@]} > 0 )); then
		exit_code=1
		printf "%sFailure%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${failure[@]}"; do
			msg_error " ${result}"
		done
	fi

	if (( ${#out_of_date[@]} > 0 )); then
		printf "%sUpgraded%s\n" "${section_separator}${BOLD}${UNDERLINE}" "${ALL_OFF}"
		section_separator=$'\n'
		for result in "${out_of_date[@]}"; do
			msg_warn " ${result}"
		done
	fi

	# Show summary when processing multiple packages
	if (( ${#pkgbases[@]} > 1 )); then
		printf '%s' "${section_separator}"
		pkgctl_version_upgrade_summary \
			"${#up_to_date[@]}" \
			"${#out_of_date[@]}" \
			"${#failure[@]}"
	fi

	# return status based on results
	return "${exit_code}"
}

pkgctl_version_upgrade_summary() {
	local up_to_date_count=$1
	local out_of_date_count=$2
	local failure_count=$3

	# print nothing if all stats are zero
	if (( up_to_date_count == 0 )) && \
			(( out_of_date_count == 0 )) && \
			(( failure_count == 0 )); then
		return 0
	fi

	# print summary for all none zero stats
	printf "%sSummary%s\n" "${BOLD}${UNDERLINE}" "${ALL_OFF}"
	if (( up_to_date_count > 0 )); then
		msg_success " Up-to-date: ${BOLD}${up_to_date_count}${ALL_OFF}" 2>&1
	fi
	if (( failure_count > 0 )); then
		msg_error " Failure: ${BOLD}${failure_count}${ALL_OFF}" 2>&1
	fi
	if (( out_of_date_count > 0 )); then
		msg_warn " Upgraded: ${BOLD}${out_of_date_count}${ALL_OFF}" 2>&1
	fi
}