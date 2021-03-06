#!/bin/sh

test_description='Test git config-set API in different settings'

. ./test-lib.sh

# 'check_config get_* section.key value' verifies that the entry for
# section.key is 'value'
check_config () {
	if test "$1" = expect_code
	then
		expect_code="$2" && shift && shift
	else
		expect_code=0
	fi &&
	op=$1 key=$2 && shift && shift &&
	if test $# != 0
	then
		printf "%s\n" "$@"
	fi >expect &&
	test_expect_code $expect_code test-config "$op" "$key" >actual &&
	test_cmp expect actual
}

test_expect_success 'setup default config' '
	cat >.git/config <<-\EOF
	[case]
		penguin = very blue
		Movie = BadPhysics
		UPPERCASE = true
		MixedCase = true
		my =
		foo
		baz = sam
	[Cores]
		WhatEver = Second
		baz = bar
	[cores]
		baz = bat
	[CORES]
		baz = ball
	[my "Foo bAr"]
		hi = mixed-case
	[my "FOO BAR"]
		hi = upper-case
	[my "foo bar"]
		hi = lower-case
	[case]
		baz = bat
		baz = hask
	[lamb]
		chop = 65
		head = none
	[goat]
		legs = 4
		head = true
		skin = false
		nose = 1
		horns
	EOF
'

test_expect_success 'get value for a simple key' '
	check_config get_value case.penguin "very blue"
'

test_expect_success 'get value for a key with value as an empty string' '
	check_config get_value case.my ""
'

test_expect_success 'get value for a key with value as NULL' '
	check_config get_value case.foo "(NULL)"
'

test_expect_success 'upper case key' '
	check_config get_value case.UPPERCASE "true" &&
	check_config get_value case.uppercase "true"
'

test_expect_success 'mixed case key' '
	check_config get_value case.MixedCase "true" &&
	check_config get_value case.MIXEDCASE "true" &&
	check_config get_value case.mixedcase "true"
'

test_expect_success 'key and value with mixed case' '
	check_config get_value case.Movie "BadPhysics"
'

test_expect_success 'key with case sensitive subsection' '
	check_config get_value "my.Foo bAr.hi" "mixed-case" &&
	check_config get_value "my.FOO BAR.hi" "upper-case" &&
	check_config get_value "my.foo bar.hi" "lower-case"
'

test_expect_success 'key with case insensitive section header' '
	check_config get_value cores.baz "ball" &&
	check_config get_value Cores.baz "ball" &&
	check_config get_value CORES.baz "ball" &&
	check_config get_value coreS.baz "ball"
'

test_expect_success 'key with case insensitive section header & variable' '
	check_config get_value CORES.BAZ "ball" &&
	check_config get_value cores.baz "ball" &&
	check_config get_value cores.BaZ "ball" &&
	check_config get_value cOreS.bAz "ball"
'

test_expect_success 'find value with misspelled key' '
	check_config expect_code 1 get_value "my.fOo Bar.hi" "Value not found for \"my.fOo Bar.hi\""
'

test_expect_success 'find value with the highest priority' '
	check_config get_value case.baz "hask"
'

test_expect_success 'find integer value for a key' '
	check_config get_int lamb.chop 65
'

test_expect_success 'find string value for a key' '
	check_config get_string case.baz hask &&
	check_config expect_code 1 get_string case.ba "Value not found for \"case.ba\""
'

test_expect_success 'check line error when NULL string is queried' '
	test_expect_code 128 test-config get_string case.foo 2>result &&
	test_i18ngrep "fatal: .*case\.foo.*\.git/config.*line 7" result
'

test_expect_success 'find integer if value is non parse-able' '
	check_config expect_code 128 get_int lamb.head
'

test_expect_success 'find bool value for the entered key' '
	check_config get_bool goat.head 1 &&
	check_config get_bool goat.skin 0 &&
	check_config get_bool goat.nose 1 &&
	check_config get_bool goat.horns 1 &&
	check_config get_bool goat.legs 1
'

test_expect_success 'find multiple values' '
	check_config get_value_multi case.baz sam bat hask
'

test_expect_success 'find value from a configset' '
	cat >config2 <<-\EOF &&
	[case]
		baz = lama
	[my]
		new = silk
	[case]
		baz = ball
	EOF
	echo silk >expect &&
	test-config configset_get_value my.new config2 .git/config >actual &&
	test_cmp expect actual
'

test_expect_success 'find value with highest priority from a configset' '
	echo hask >expect &&
	test-config configset_get_value case.baz config2 .git/config >actual &&
	test_cmp expect actual
'

test_expect_success 'find value_list for a key from a configset' '
	cat >except <<-\EOF &&
	sam
	bat
	hask
	lama
	ball
	EOF
	test-config configset_get_value case.baz config2 .git/config >actual &&
	test_cmp expect actual
'

test_expect_success 'proper error on non-existent files' '
	echo "Error (-1) reading configuration file non-existent-file." >expect &&
	test_expect_code 2 test-config configset_get_value foo.bar non-existent-file 2>actual &&
	test_cmp expect actual
'

test_expect_success POSIXPERM,SANITY 'proper error on non-accessible files' '
	chmod -r .git/config &&
	test_when_finished "chmod +r .git/config" &&
	echo "Error (-1) reading configuration file .git/config." >expect &&
	test_expect_code 2 test-config configset_get_value foo.bar .git/config 2>actual &&
	test_cmp expect actual
'

test_expect_success 'proper error on error in default config files' '
	cp .git/config .git/config.old &&
	test_when_finished "mv .git/config.old .git/config" &&
	echo "[" >>.git/config &&
	echo "fatal: bad config file line 34 in .git/config" >expect &&
	test_expect_code 128 test-config get_value foo.bar 2>actual &&
	test_cmp expect actual
'

test_expect_success 'proper error on error in custom config files' '
	echo "[" >>syntax-error &&
	echo "fatal: bad config file line 1 in syntax-error" >expect &&
	test_expect_code 128 test-config configset_get_value foo.bar syntax-error 2>actual &&
	test_cmp expect actual
'

test_expect_success 'check line errors for malformed values' '
	mv .git/config .git/config.old &&
	test_when_finished "mv .git/config.old .git/config" &&
	cat >.git/config <<-\EOF &&
	[alias]
		br
	EOF
	test_expect_code 128 git br 2>result &&
	test_i18ngrep "fatal: .*alias\.br.*\.git/config.*line 2" result
'

test_expect_success 'error on modifying repo config without repo' '
	mkdir no-repo &&
	(
		GIT_CEILING_DIRECTORIES=$(pwd) &&
		export GIT_CEILING_DIRECTORIES &&
		cd no-repo &&
		test_must_fail git config a.b c 2>err &&
		grep "not in a git directory" err
	)
'

test_done
