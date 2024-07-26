#!/bin/sh
#
# Copyright (c) 2017 The NetBSD Foundation, Inc.
# All rights reserved.
#
# This code is derived from software contributed to The NetBSD Foundation
# by Johnny C. Lam.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE NETBSD FOUNDATION, INC. AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

SELF=${0##*/}

debug=:
debug()
{
	echo 1>&2 "#" "$@"
}

###
# Functions to treat whitespace-separated strings as "list" and "set"
# data structures.
#
# A list is a string whose elements are the words in the string.
#
#	list_prepend
#	list_append
#	list_pop
#	list_top
#
# A set is a list whose elements are unique.
#
#	set_add
#	set_remove
#	set_has_member

list_append()
{
	_rcla_list=${1}; shift
	_rcla_value=

	eval _rcla_value='${'"${_rcla_list}"'}'
	if [ -n "${_rcla_value}" ]; then
		# add to end of list
		_rcla_value="${_rcla_value} ${*}"
	else
		_rcla_value=${*}
	fi
	${debug} "${_rcla_list} = [ ${_rcla_value} ]"
	eval "${_rcla_list}"='"${_rcla_value}"'
}

list_prepend()
{
	_rclp_list=${1}; shift
	_rclp_value=

	eval _rclp_value='${'"${_rclp_list}"'}'
	if [ -n "${_rclp_value}" ]; then
		# add to head of list
		_rclp_value="${*} ${_rclp_value}"
	else
		_rclp_value=${*}
	fi
	${debug} "${_rclp_list} = [ ${_rclp_value} ]"
	eval "${_rclp_list}"='"${_rclp_value}"'
}

list_pop()
{
	_rclpop_list=${1}; shift
	_rclpop_value=

	eval _rclpop_value='${'"${_rclpop_list}"'}'
	# remove last element of list
	case ${_rclpop_value} in
	*" "*)
		_rclpop_value=${_rclpop_value% *}
		;;
	*)
		_rclpop_value=
		;;
	esac
	${debug} "${_rclpop_list} = [ ${_rclpop_value} ]"
	eval "${_rclpop_list}"='"${_rclpop_value}"'
}

list_top()
{
	_rclt_list=${1}; shift
	_rclt_value=
	_rclt_top=

	eval _rclt_value='${'"${_rclt_list}"'}'
	# get last element of list
	case ${_rclt_value} in
	*" "*)
		_rclt_top=${_rclt_value##* }
		;;
	*)
		_rclt_top=${_rclt_value}
		;;
	esac
	echo "${_rclt_top}"
}

set_add()
{
	_rcsa_set=${1}; shift
	_rcsa_value=
	_rcsa_element=
	_rcsa_result=0

	eval _rcsa_value='${'"${_rcsa_set}"'}'
	for _rcsa_element; do
		case " ${_rcsa_value} " in
		*" ${_rcsa_element} "*)
			# element is a member of the set.
			_rcsa_result=1
			;;
		*)
			if [ -n "${_rcsa_value}" ]; then
				${debug} "${_rcsa_set} += { ${_rcsa_element} }"
				_rcsa_value="${_rcsa_value} ${_rcsa_element}"
			else
				${debug} "${_rcsa_set} = { ${_rcsa_element} }"
				_rcsa_value=${_rcsa_element}
			fi
			;;
		esac
	done
	[ -z "${_rcsa_value}" ] || eval "${_rcsa_set}"='"${_rcsa_value}"'

	return ${_rcsa_result}
}

set_remove()
{
	_rcsr_set=${1}; shift
	_rcsr_value=
	_rcsr_element=

	eval _rcsr_value='${'"${_rcsr_set}"'}'
	_rcsr_old_value=${_rcsr_value}
	_rcsr_removed=
	for _rcsr_element; do
		_rcsr_removed=
		case " ${_rcsr_value} " in
		" ${_rcsr_element} ")
			# element is the sole member.
			_rcsr_removed=yes; _rcsr_value=
			;;
		" ${_rcsr_element} "*)
			# element is the first member listed.
			_rcsr_removed=yes; _rcsr_value=${_rcsr_value#* }
			;;
		*" ${_rcsr_element} ")
			# element is the last member listed.
			_rcsr_removed=yes; _rcsr_value=${_rcsr_value% *}
			;;
		*" ${_rcsr_element} "*)
			# $element is somewhere in the middle of the list.
			_rcsr_removed=yes
			_rcsr_value="${_rcsr_value% "${_rcsr_element}" *} ${_rcsr_value#* "${_rcsr_element}" }"
			;;
		esac
		[ -z "${_rcsr_removed}" ] || ${debug} "${_rcsr_set} -= { ${_rcsr_element} }"
	done
	[ "${_rcsr_old_value}" = "${_rcsr_value}" ] || eval "${_rcsr_set}"='"${_rcsr_value}"'
}

set_has_member()
{
	_rcshm_set=${1}; shift
	_rcshm_value=
	_rcshm_element=

	eval _rcshm_value='${'"${_rcshm_set}"'}'
	for _rcshm_element; do
		case " ${_rcshm_value} " in
		*" ${_rcshm_element} "*)
			: "element is a member of the set"
			;;
		*)
			return 1
			;;
		esac
	done

	return 0
}

###
# Functions to simulate a table data structure using global environment
# variables.
#
# A table is a mapping of keys to values.  The reference "table[key]"
# is converted into the global environment variable "${table}___${key}".
#
# A key is restricted to a string that contains valid symbols for
# shell variable names.
#
# A value is any valid string.

table_get()
{
	_rctg_table=${1}; shift
	_rctg_key=${1}; shift
	_rctg_var="${_rctg_table}___${_rctg_key}"

	eval echo '${'"${_rctg_var}"'}'
}

table_set()
{
	_rcts_table=${1}; shift
	_rcts_key=${1}; shift
	_rcts_value=${1}; shift
	_rcts_var="${_rcts_table}___${_rcts_key}"

	_rcts_old_value=
	eval _rcts_old_value='${'"${_rcts_var}"'}'
	if [ "${_rcts_old_value}" != "${_rcts_value}" ]; then
		${debug} "${_rcts_table}[${_rcts_key}] = ${_rcts_value}"
		eval "${_rcts_var}"='"${_rcts_value}"'
		return 0
	fi
	return 1
}

###
# Global variables:
#
# FILE is the table of files to parse.
#
# KEYS is a list of valid keys for the FILE table.
#
# BEFORE is a table of lists of provisions whose providers must appear
#	in the final sequence after FILE[n], for each n in ${KEYS}.
#
# KEYWORD is a table of lists of keywords associated with FILE[n], for
#	each n in ${KEYS}.
#
# PROVIDE is the table of lists of provision for FILE[n], for each n
#	in ${KEYS}.
#
# PROVIDER is a table that maps a provision to the list of keys into
#	the FILE table that provide it.
#
# REQUIRE is the table of lists of provisions whose providers must appear
#	in the final sequence before FILE[n], for each n in ${KEYS}.
#
# KEEP_LIST is a list of keywords, one of which must be listed in
#	KEYWORD[n] for FILE[n] to be emitted to standard output.
#
# SKIP_LIST is a list of keywords, none of which can be listed in
#	KEYWORD[n] for FILE[n] to be emitted to standard output.
#
# SORTED is the list of keys in topological order.

KEYS=
KEEP_LIST=
SKIP_LIST=

###

parse_file()
{
	index=${1}; shift
	file=${1}; shift

	# Initialize to empty strings to override any inherited values.
	for table in BEFORE KEYWORD PROVIDE REQUIRE; do
		table_set "${table}" "${index}" ""
	done

	# Scan through the file looking for a block containing a series
	# of "REQUIRE", "PROVIDE", "BEFORE", and "KEYWORD" lines.
	found=
	line=; table=; list=; provision=; keys=
	while IFS= read -r line; do
		case ${line} in
		"# BEFORE: "*|\
		"# KEYWORD: "*|"# KEYWORDS: "*|\
		"# PROVIDE: "*|"# PROVIDES: "*|\
		"# REQUIRE: "*|"# REQUIRES: "*)
			found=yes
			table=${line#* }; table=${table%%:*}; table=${table%S}
			list=${line#*: }
			if [ "${table}" = "PROVIDE" ]; then
				# Set a placeholder provision so that every
				# file provides *something* that can be
				# listed in REQUIRE.
				: "${list:=__rcorder_${index}}"
				for provision in ${list}; do
					keys=$(table_get PROVIDER "${provision}")
					set_add keys "${index}"
					table_set PROVIDER "${provision}" "${keys}"
				done
			fi
			[ -z "${list}" ] || table_set "${table}" "${index}" "${list}"
			;;
		*)
			if [ -z "${found}" ]; then
				continue
			fi
			# read past the block, so stop parsing
			break
			;;
		esac
	done < "${file}"
}

initialize()
{
	# Global KEYS variable.
	KEYS=

	# Add each file into the FILE table, indexed by the order given.
	# Parse files for keyword blocks.
	# Set KEYS to complete list of valid keys into FILE table.
	#
	file=
	index=1
	while [ ${#} -gt 0 ]; do
		file=${1}; shift
		[ -f "${file}" ] || continue
		table_set FILE "${index}" "${file}"
		parse_file "${index}" "${file}"
		list_prepend KEYS "${index}"	# prepend to match rcorder(8)
		index=$(( index + 1 ))
	done

	# Convert BEFORE into REQUIRE and vice-versa by observing that
	# "a BEFORE b" is equivalent to "b REQUIRE a" with respect to
	# topological sorting.
	#
	i=; j=; keys=
	provide_list=; before=; before_list=; require=; require_list=

	for i in ${KEYS}; do
		provide_list=$(table_get PROVIDE "${i}")	# guaranteed non-empty

		before_list=$(table_get BEFORE "${i}")
		if [ -n "${before_list}" ]; then
			for before in ${before_list}; do
				keys=$(table_get PROVIDER "${before}")
				for j in ${keys}; do
					require_list=$(table_get REQUIRE "${j}")
					# shellcheck disable=SC2086
					set_add require_list ${provide_list}
					table_set REQUIRE "${j}" "${require_list}"
				done
			done
		fi

		require_list=$(table_get REQUIRE "${i}")
		if [ -n "${require_list}" ]; then
			for require in ${require_list}; do
				keys=$(table_get PROVIDER "${require}")
				for j in ${keys}; do
					before_list=$(table_get BEFORE "${j}")
					# shellcheck disable=SC2086
					set_add before_list ${provide_list}
					table_set BEFORE "${j}" "${before_list}"
				done
			done
		fi
	done

	# POSTCONDITION: The REQUIRE and BEFORE tables each hold the entire
	#	directed graph between provisions.
}

tsort_dfs()
{
	# Non-recursive implementation of topological sort using DFS.

	# Global list of nodes in topological order.
	SORTED=

	STACK=	# stack of visited nodes
	# shellcheck disable=SC2034
	GREY=	# visited nodes whose children need to be visited
	# shellcheck disable=SC2034
	BLACK=	# visited nodes whose children have been visited

	i=; j=; k=; keys=
	require=; require_list=
	file=

	for i in ${KEYS}; do
		set_has_member BLACK "${i}" && continue
		if set_has_member GREY "${i}"; then
			file=$(table_get FILE "${i}")
			echo 1>&2 "Circular dependency on file ${file}, aborting."
			return 1
		fi
		list_append STACK "${i}"

		while [ -n "${STACK}" ]; do
			j=$(list_top STACK)
			if set_has_member BLACK "${j}"; then
				list_pop STACK
				continue
			fi
			if set_add GREY "${j}"; then
				require_list=$(table_get REQUIRE "${j}")
				[ -n "${require_list}" ] || continue
				for require in ${require_list}; do
					keys=$(table_get PROVIDER "${require}")
					if [ -z "${keys}" ]; then
						echo 1>&2 "${SELF}: requirement ${require} has no providers."
					fi
					for k in ${keys}; do
						set_has_member BLACK "${k}" && continue
						if set_has_member GREY "${k}"; then
							echo 1>&2 "Circular dependency on provision ${require}, aborting."
							return 1
						fi
						list_append STACK "${k}"
					done
				done
			else
				list_pop STACK
				set_add BLACK "${j}"
				list_append SORTED "${j}"
			fi
		done
	done

	return 0
}

tsort_kahn()
{
	# Topological sort using Kahn's algorithm.

	# Global list of nodes in topological order.
	SORTED=

	# Populate ${SOURCES} with nodes with no incoming edges.
	SOURCES=
	i=
	for i in ${KEYS}; do
		before_list=$(table_get BEFORE "${i}")
		[ -n "${before_list}" ] || set_add SOURCES "${i}"
	done

	j=; keys=
	provide_list=; require=; require_list=; before_list=
	while [ -n "${SOURCES}" ]; do
		${debug} "<looping>: [ ${SOURCES} ]"
		i=$(list_top SOURCES); list_pop SOURCES
		list_prepend SORTED "${i}"
		provide_list=$(table_get PROVIDE "${i}")	# guaranteed non-empty
		require_list=$(table_get REQUIRE "${i}")
		[ -n "${require_list}" ] || continue
		table_set REQUIRE "${i}" ""
		for require in ${require_list}; do
			keys=$(table_get PROVIDER "${require}")
			for j in ${keys}; do
				# remove edges from $i to $j
				before_list=$(table_get BEFORE "${j}")
				# shellcheck disable=SC2086
				set_remove before_list ${provide_list}
				table_set BEFORE "${j}" "${before_list}"
				[ -n "${before_list}" ] || set_add SOURCES "${j}"
			done
		done
	done

	# If the graph still has edges, it's not acyclic.
	file=
	for i in ${KEYS}; do
		before_list=$(table_get BEFORE "${i}")
		if [ -n "${before_list}" ]; then
			file=$(table_get FILE "${i}")
			echo 1>&2 "Circular dependency on file ${file}, aborting."
			return 1
		fi
	done

	return 0
}

keep_ok()
{
	# Return 0 if any of the keywords in the parameters are
	# in ${KEEP_LIST}; otherwise return 1.

	if [ -n "${KEEP_LIST}" ]; then
		word=
		for word; do
			if set_has_member KEEP_LIST "${word}"; then
				return 0
			fi
		done
		return 1
	fi
	# empty ${KEEP_LIST} means keep everything.
	return 0
}

skip_ok()
{
	# Return 1 if any of the keywords in the parameters are
	# in ${SKIP_LIST}; otherwise return 0.

	if [ -n "${SKIP_LIST}" ]; then
		word=
		for word; do
			if set_has_member SKIP_LIST "${word}"; then
				return 1
			fi
		done
	fi
	return 0
}

usage()
{
	echo 1>&2 "Usage: ${SELF} [-k keep] [-s skip] file ..."
	exit 127
}

main()
{
	# Global keep and skip keyword lists.
	KEEP_LIST=
	SKIP_LIST=

	arg=
	OPTIND=1
	while getopts ":k:s:" arg "${@}"; do
		case ${arg} in
		k)	set_add KEEP_LIST "${OPTARG}" ;;
		s)	set_add SKIP_LIST "${OPTARG}" ;;
		*)	usage ;;
		esac
	done
	shift $(( OPTIND - 1 ))

	: "${RCORDER_TSORT:=dfs}"

	tsort=
	case ${RCORDER_TSORT} in
	dfs)
		tsort="tsort_dfs"
		;;
	kahn)
		tsort="tsort_kahn"
		;;
	*)
		echo 1>&2 "${SELF}: unknown algorithm '${RCORDER_TSORT}', using 'dfs'"
		tsort="tsort_dfs"
		;;
	esac

	initialize "${@}"
	${tsort} || return 1

	i=; keyword_list=; file=
	for i in ${SORTED}; do
		keyword_list=$(table_get KEYWORD "${i}")
		# shellcheck disable=SC2086
		if skip_ok ${keyword_list} && keep_ok ${keyword_list}; then
			file=$(table_get FILE "${i}")
			echo "${file}"
		fi
	done

	return 0
}

main "${@}"
