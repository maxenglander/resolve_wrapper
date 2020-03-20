#include "config.h"

#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include <cmocka.h>

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

#include <netinet/in.h>
#include <arpa/nameser.h>
#include <arpa/inet.h>
#include <resolv.h>

#define RWRAP_RESOLV_CONF_TMPL "rwrap_resolv_conf_XXXXXX"

struct resolv_conf_test_state {
	int rc_fd;
	FILE *resolv_conf;
	char *resolv_conf_path;
};

static int setup(void **state)
{
	struct resolv_conf_test_state *test_state;

	test_state = malloc(sizeof(struct resolv_conf_test_state));
	assert_non_null(test_state);
	test_state->rc_fd = -1;
	test_state->resolv_conf = NULL;

	test_state->resolv_conf_path = strdup(RWRAP_RESOLV_CONF_TMPL);
	assert_non_null(test_state->resolv_conf_path);
	test_state->rc_fd = mkstemp(test_state->resolv_conf_path);
	assert_non_null(test_state->resolv_conf_path);
	test_state->resolv_conf = fdopen(test_state->rc_fd, "a");
	assert_non_null(test_state->resolv_conf);

	*state = test_state;

	return 0;
}

static int teardown(void **state)
{
	struct resolv_conf_test_state *test_state;

	test_state = (struct resolv_conf_test_state *) *state;

	if (test_state == NULL) return -1;

	if (test_state->resolv_conf) {
		fclose(test_state->resolv_conf);
	}

	if (test_state->rc_fd != -1) {
		close(test_state->rc_fd);
	}

	if (test_state->resolv_conf_path) {
		unlink(test_state->resolv_conf_path);
		free(test_state->resolv_conf_path);
	}

	free(test_state);

	return 0;
}

static void test_res_ninit(void **state)
{
	struct resolv_conf_test_state *test_state;
	struct __res_state dnsstate;
	/*
	 * libc resolver only supports 3 name servers. Make sure the
	 * extra are skipped for both v4 and v6. Also make sure there's
	 * 'too many' nameservers even on platforms where v6 is not
	 * supported.
	 */
	const char *nameservers[] = {
		"127.0.0.1",
		"10.10.10.1",
		"fd53:53:53:53::1011",
		"10.10.10.2",
		"10.10.10.3",
		"fd53:53:53:53::1012",
		NULL,
	};
	int i;
	int rv;
	char straddr[INET6_ADDRSTRLEN] = { '\0' };
#ifdef HAVE_RES_SOCKADDR_UNION_SIN
	union res_sockaddr_union set[MAXNS*5];
#endif
#ifdef HAVE_RES_STATE_U_EXT_NSADDRS
	struct sockaddr_in6 *sa6;
#endif

	test_state = (struct resolv_conf_test_state *) *state;

	/*
	 * Write a valid resolv.conf.
	 * Make sure it's possible to skip comments
	 */
	fputs("# Hello world\n", test_state->resolv_conf);
	fputs("; This is resolv_wrapper\n", test_state->resolv_conf);
	for (i = 0; nameservers[i]; i++) {
		fputs("nameserver ", test_state->resolv_conf);
		fputs(nameservers[i], test_state->resolv_conf);
		fputs("\n", test_state->resolv_conf);
	}
	fflush(test_state->resolv_conf);

	rv = setenv("RESOLV_WRAPPER_CONF", test_state->resolv_conf_path, 1);
	assert_int_equal(rv, 0);

	memset(&dnsstate, 0, sizeof(dnsstate));
	rv = res_ninit(&dnsstate);
	unsetenv("RESOLV_WRAPPER_CONF");
	assert_int_equal(rv, 0);

	/*
	 * Validate the number of parsed name servers.
	*
	 * On platforms that don't support IPv6, the v6 address is skipped
	 * and we end up reading three v4 addresses.
	 *
	 * test we have two v4 and one v6 server
	 *
	 * Note: This test assumes MAXNS == 3, which is the
	 * case on all systems encountered so far.
	 */
	assert_int_equal(MAXNS, 3);
#ifdef HAVE_RES_SOCKADDR_UNION_SIN
	memset(set, 0, sizeof(set));
	rv = res_getservers(&dnsstate, set, MAXNS+5);
	assert_int_equal(rv, MAXNS);

	/* IPv4 */
	assert_int_equal(set[0].sin.sin_family, AF_INET);
	assert_int_equal(set[0].sin.sin_port, htons(53));
	inet_ntop(AF_INET, &(set[0].sin.sin_addr),
		  straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[0], straddr);

	assert_int_equal(set[1].sin.sin_family, AF_INET);
	assert_int_equal(set[1].sin.sin_port, htons(53));
	inet_ntop(AF_INET, &(set[1].sin.sin_addr), straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[1], straddr);

#ifdef HAVE_RES_SOCKADDR_UNION_SIN6
	/* IPv6 */
	assert_int_equal(set[2].sin6.sin6_family, AF_INET6);
	assert_int_equal(set[2].sin6.sin6_port, htons(53));
	inet_ntop(AF_INET6, &(set[2].sin6.sin6_addr), straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[2], straddr);
#else /* ! HAVE_RES_SOCKADDR_UNION_SIN6 */
	/*
	 * On platforms that don't support IPv6, the v6 address is skipped
	 * and we end up reading three v4 addresses.
	 */
	assert_int_equal(set[2].sin.sin_family, AF_INET);
	assert_int_equal(set[2].sin.sin_port, htons(53));
	inet_ntop(AF_INET, &(set[2].sin.sin_addr), straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[3], straddr);
#endif /* ! HAVE_RES_SOCKADDR_UNION_SIN6 */

#else /* ! HAVE_RES_SOCKADDR_UNION_SIN */
	assert_int_equal(dnsstate.nscount, MAXNS);

	/* Validate the servers. */

	/* IPv4 */
	assert_int_equal(dnsstate.nsaddr_list[0].sin_family, AF_INET);
	assert_int_equal(dnsstate.nsaddr_list[0].sin_port, htons(53));
	inet_ntop(AF_INET, &(dnsstate.nsaddr_list[0].sin_addr),
		  straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[0], straddr);
#ifdef HAVE_RES_STATE_U_EXT_NSADDRS
	assert_null(dnsstate._u._ext.nsaddrs[0]);
#endif

	assert_int_equal(dnsstate.nsaddr_list[1].sin_family, AF_INET);
	assert_int_equal(dnsstate.nsaddr_list[1].sin_port, htons(53));
	inet_ntop(AF_INET, &(dnsstate.nsaddr_list[1].sin_addr),
		  straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[1], straddr);
#ifdef HAVE_RES_STATE_U_EXT_NSADDRS
	assert_null(dnsstate._u._ext.nsaddrs[1]);
#endif

#ifdef HAVE_RES_STATE_U_EXT_NSADDRS
	/* IPv6 */
	assert_non_null(dnsstate._u._ext.nsaddrs[2]);
	sa6 = dnsstate._u._ext.nsaddrs[2];
	assert_int_equal(sa6->sin6_family, AF_INET6);
	assert_int_equal(sa6->sin6_port, htons(53));
	inet_ntop(AF_INET6, &(sa6->sin6_addr), straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[2], straddr);
#else
	/*
	 * On platforms that don't support IPv6, the v6 address is skipped
	 * and we end up reading three v4 addresses.
	 */
	assert_int_equal(dnsstate.nsaddr_list[2].sin_family, AF_INET);
	assert_int_equal(dnsstate.nsaddr_list[2].sin_port, htons(53));
	inet_ntop(AF_INET, &(dnsstate.nsaddr_list[2].sin_addr),
		  straddr, INET6_ADDRSTRLEN);
	assert_string_equal(nameservers[3], straddr);
#endif

#endif /* ! HAVE_RES_SOCKADDR_UNION_SIN */

	res_nclose(&dnsstate);
}

static void test_res_ninit_enoent(void **state)
{
	int rv;
	struct __res_state dnsstate;

	(void) state; /* unused */

	rv = setenv("RESOLV_WRAPPER_CONF", "/no/such/file", 1);
	assert_int_equal(rv, 0);

	/* Just make sure we don't crash, error is fine */
	memset(&dnsstate, 0, sizeof(dnsstate));
	rv = res_ninit(&dnsstate);
	unsetenv("RESOLV_WRAPPER_CONF");
	assert_int_equal(rv, -1);
}

int main(void) {
	int rc;

	const struct CMUnitTest init_tests[] = {
		cmocka_unit_test_setup_teardown(test_res_ninit, setup, teardown),
		cmocka_unit_test(test_res_ninit_enoent),
	};

	rc = cmocka_run_group_tests(init_tests, NULL, NULL);

	return rc;
}
