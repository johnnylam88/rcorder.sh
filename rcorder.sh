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
#	set_has_member

list_append()
{
	local list="$1"; shift
	local value
	eval value=\"\${$list}\"
	if [ -n "$value" ]; then
		# add to end of list
		value="$value ""$@"
	else
		value="$@"
	fi
	$debug "$list = [ $value ]"
	eval "$list='$value'"
}

list_prepend()
{
	local list="$1"; shift
	local value
	eval value=\"\${$list}\"
	if [ -n "$value" ]; then
		# add to head of list
		value="$@"" $value"
	else
		value="$@"
	fi
	$debug "$list = [ $value ]"
	eval "$list='$value'"
}

list_pop()
{
	local list="$1"; shift
	local value
	eval value=\"\${$list}\"
	# remove last element of list
	case $value in
	*" "*)	value=${value% *} ;;
	*)	value= ;;
	esac
	$debug "$list = [ $value ]"
	eval "$list='$value'"
}

list_top()
{
	local list="$1"; shift
	local value top
	eval value=\"\${$list}\"
	# get last element of list
	case $value in
	*" "*)	top=${value##* } ;;
	*)	top=$value ;;
	esac
	echo "$top"
}

set_add()
{
	local _set="$1"; shift
	local value element
	eval value=\"\${$_set}\"
	local result=0
	for element; do
		case " $value " in
		*" $element "*)
			# $element is a member of the set.
			result=1 ;;
		*)	if [ -n "$value" ]; then
				$debug "$_set += { $element }"
				value="$value $element"
			else
				$debug "$_set = { $element }"
				value="$element"
			fi ;;
		esac
	done
	[ -z "$value" ] || eval "$_set='$value'"
	return $result
}

set_has_member()
{
	local _set="$1"; shift
	local value element
	eval value=\"\${$_set}\"
	for element; do
		case " $value " in
		*" $element "*)
			: "$element is a member of the set" ;;
		*)	return 1 ;;
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
	local table="$1"; shift
	local key="$1"; shift
	local var="${table}___${key}"
	eval echo \"\${$var}\"
}

table_set()
{
	local table="$1"; shift
	local key="$1"; shift
	local value="$1"; shift
	local var="${table}___${key}"
	local old_value
	eval old_value=\"\${$var}\"
	if [ "$old_value" != "$value" ]; then
		$debug "$table[$key] = $value"
		eval "$var='$value'"
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

KEYS=
KEEP_LIST=
SKIP_LIST=

###

parse_file()
{
	local index="$1"; shift
	local file="$1"; shift

	# Initialize to empty strings to override any inherited values.
	local table
	for table in BEFORE KEYWORD PROVIDE REQUIRE; do
		table_set $table $index ""
	done

	# Scan through the file looking for a block containing a series
	# of "REQUIRE", "PROVIDE", "BEFORE", and "KEYWORD" lines.
	local found=
	local line table list provision keys
	while IFS= read line; do
		case $line in
		"# BEFORE: "*|\
		"# KEYWORD: "*|"# KEYWORDS: "*|\
		"# PROVIDE: "*|"# PROVIDES: "*|\
		"# REQUIRE: "*|"# REQUIRES: "*)
			found="yes"
			table=${line#* }; table=${table%%:*}; table=${table%S}
			list=${line#*: }
			if [ "$table" = "PROVIDE" ]; then
				# Set a placeholder provision so that every
				# file provides *something* that can be
				# listed in REQUIRE.
				: ${list:=__rcorder_$index}
				for provision in $list; do
					keys=$(table_get PROVIDER $provision)
					set_add keys $index
					table_set PROVIDER $provision "$keys"
				done
			fi
			[ -z "$list" ] || table_set "$table" "$index" "$list" ;;
		*)
			if [ -z "$found" ]; then
				continue
			else
				# read past the block, so stop parsing
				break
			fi ;;
		esac
	done < $file
}

initialize()
{
	# Global KEYS variable.
	KEYS=

	# Add each file into the FILE table, indexed by the order given.
	# Parse files for keyword blocks.
	# Set KEYS to complete list of valid keys into FILE table.
	#
	local file
	local index=1
	while [ $# -gt 0 ]; do
		file="$1"; shift
		[ -f "$file" ] || continue
		table_set FILE $index "$file"
		parse_file $index "$file"
		list_prepend KEYS $index	# prepend to match rcorder(8)
		index=$(( $index + 1 ))
	done

	# Convert BEFORE into REQUIRE by observing that "a BEFORE b"
	# is equivalent to "b REQUIRE a" with respect to topological
	# sorting.
	#
	local i j keys
	local before before_list provide_list require_list
	for i in ${KEYS}; do
		before_list=$(table_get BEFORE $i)
		[ -n "$before_list" ] || continue
		provide_list=$(table_get PROVIDE $i)
		# $provide_list is guaranteed to be non-empty.
		for before in $before_list; do
			keys=$(table_get PROVIDER $before)
			for j in $keys; do
				require_list=$(table_get REQUIRE $j)
				set_add require_list $provide_list
				table_set REQUIRE $j "$require_list"
			done
		done
	done

	# POSTCONDITION: The REQUIRE table holds the entire directed
	#	graph between provisions.
}

tsort_dfs()
{
	# Non-recursive implementation of topological sort using DFS.

	local STACK=	# stack of visited nodes
	local GREY=	# visited nodes whose children need to be visited
	local BLACK=	# visited nodes whose children have been visited
	local SORTED=	# sorted list of nodes (by key)

	local i j k keys
	local require require_list
	local file
	for i in ${KEYS}; do
		set_has_member BLACK $i && continue
		if set_has_member GREY $i; then
			file=$(table_get FILE $i)
			echo 1>&2 "Circular dependency on file $file, aborting."
			return 1
		fi
		list_append STACK $i

		while [ -n "${STACK}" ]; do
			j=$(list_top STACK)
			if set_has_member BLACK $j; then
				list_pop STACK
				continue
			fi
			if set_add GREY $j; then
				require_list=$(table_get REQUIRE $j)
				[ -n "$require_list" ] || continue
				for require in $require_list; do
					keys=$(table_get PROVIDER $require)
					if [ -z "$keys" ]; then
						echo 1>&2 "${SELF}: Requirement $require has no providers, aborting."
						return 1
					fi
					for k in $keys; do
						set_has_member BLACK $k && continue
						if set_has_member GREY $k; then
							echo 1>&2 "Circular dependency on provision $require, aborting."
							return 1
						fi
						list_append STACK $k
					done
				done
			else
				list_pop STACK
				set_add BLACK $j
				list_append SORTED $j
			fi
		done
	done
	echo "${SORTED}"
}

keep_ok()
{
	# Return 0 if any of the keywords in the parameters are
	# in ${KEEP_LIST}; otherwise return 1.

	if [ -n "${KEEP_LIST}" ]; then
		local word
		for word; do
			if set_has_member KEEP_LIST "$word"; then
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
		local word
		for word; do
			if set_has_member SKIP_LIST "$word"; then
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

	local arg
	local OPTIND=1
	while getopts ":k:s:" arg "$@"; do
		case $arg in
		k)	set_add KEEP_LIST "${OPTARG}" ;;
		s)	set_add SKIP_LIST "${OPTARG}" ;;
		*)	usage ;;
		esac
	done
	shift $(( ${OPTIND} - 1 ))

	initialize "$@"
	local keys="$(tsort_dfs)" || return 1

	local i keyword_list file
	for i in $keys; do
		keyword_list=$(table_get KEYWORD $i)
		if skip_ok $keyword_list && keep_ok $keyword_list; then
			file=$(table_get FILE $i)
			echo "$file"
		fi
	done
	return 0
}

main "$@"
