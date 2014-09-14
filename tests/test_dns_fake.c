/*
 * Copyright (C) Jakub Hrozek 2014 <jakub.hrozek@gmail.com>
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the author nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include <cmocka.h>

#include "config.h"

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

#include <netinet/in.h>
#include <arpa/nameser.h>
#include <arpa/inet.h>
#include <resolv.h>

#define ANSIZE 256

static void test_res_fake_a_query(void **state)
{
	int rv;
	struct __res_state dnsstate;
	unsigned char answer[ANSIZE];
	char addr[INET_ADDRSTRLEN];
	ns_msg handle;
	ns_rr rr;   /* expanded resource record */

	(void) state; /* unused */

	memset(&dnsstate, 0, sizeof(struct __res_state));
	rv = res_ninit(&dnsstate);
	assert_int_equal(rv, 0);

	rv = res_nquery(&dnsstate, "cwrap.org", ns_c_in, ns_t_a,
			answer, ANSIZE);
	assert_int_not_equal(rv, -1);

	ns_initparse(answer, 256, &handle);
	/* The query must finish w/o an error, have one answer and the answer
	 * must be a parseable RR of type A and have the address that our
	 * fake hosts file contains
	 */
	assert_int_equal(ns_msg_getflag(handle, ns_f_rcode), ns_r_noerror);
	assert_int_equal(ns_msg_count(handle, ns_s_an), 1);
	assert_int_equal(ns_parserr(&handle, ns_s_an, 0, &rr), 0);
	assert_int_equal(ns_rr_type(rr), ns_t_a);
	assert_non_null(inet_ntop(AF_INET, ns_rr_rdata(rr), addr, 256));
	assert_string_equal(addr, "127.0.0.21");
}

static void test_res_fake_a_query_notfound(void **state)
{
	int rv;
	struct __res_state dnsstate;
	unsigned char answer[ANSIZE];
	ns_msg handle;

	(void) state; /* unused */

	memset(&dnsstate, 0, sizeof(struct __res_state));
	rv = res_ninit(&dnsstate);
	assert_int_equal(rv, 0);

	rv = res_nquery(&dnsstate, "nosuchentry.org", ns_c_in, ns_t_a,
			answer, ANSIZE);
	assert_int_not_equal(rv, -1);

	ns_initparse(answer, 256, &handle);
	/* The query must finish w/o an error and have no answer */
	assert_int_equal(ns_msg_getflag(handle, ns_f_rcode), ns_r_noerror);
	assert_int_equal(ns_msg_count(handle, ns_s_an), 0);
}

static void test_res_fake_aaaa_query(void **state)
{
	int rv;
	struct __res_state dnsstate;
	unsigned char answer[ANSIZE];
	char addr[INET6_ADDRSTRLEN];
	ns_msg handle;
	ns_rr rr;   /* expanded resource record */

	(void) state; /* unused */

	memset(&dnsstate, 0, sizeof(struct __res_state));
	rv = res_ninit(&dnsstate);
	assert_int_equal(rv, 0);

	rv = res_nquery(&dnsstate, "cwrap6.org", ns_c_in, ns_t_aaaa,
			answer, ANSIZE);
	assert_int_not_equal(rv, -1);

	ns_initparse(answer, 256, &handle);
	/* The query must finish w/o an error, have one answer and the answer
	 * must be a parseable RR of type AAAA and have the address that our
	 * fake hosts file contains
	 */
	assert_int_equal(ns_msg_getflag(handle, ns_f_rcode), ns_r_noerror);
	assert_int_equal(ns_msg_count(handle, ns_s_an), 1);
	assert_int_equal(ns_parserr(&handle, ns_s_an, 0, &rr), 0);
	assert_int_equal(ns_rr_type(rr), ns_t_aaaa);
	assert_non_null(inet_ntop(AF_INET6, ns_rr_rdata(rr), addr, 256));
	assert_string_equal(addr, "2a00:1450:4013:c01::63");
}

static void test_res_fake_aaaa_query_notfound(void **state)
{
	int rv;
	struct __res_state dnsstate;
	unsigned char answer[ANSIZE];
	ns_msg handle;

	(void) state; /* unused */

	memset(&dnsstate, 0, sizeof(struct __res_state));
	rv = res_ninit(&dnsstate);
	assert_int_equal(rv, 0);

	rv = res_nquery(&dnsstate, "nosuchentry.org", ns_c_in, ns_t_aaaa,
			answer, ANSIZE);
	assert_int_not_equal(rv, -1);

	ns_initparse(answer, 256, &handle);
	/* The query must finish w/o an error and have no answer */
	assert_int_equal(ns_msg_getflag(handle, ns_f_rcode), ns_r_noerror);
	assert_int_equal(ns_msg_count(handle, ns_s_an), 0);
}

int main(void)
{
	int rc;

	const UnitTest tests[] = {
		unit_test(test_res_fake_a_query),
		unit_test(test_res_fake_a_query_notfound),
		unit_test(test_res_fake_aaaa_query),
		unit_test(test_res_fake_aaaa_query_notfound),
	};

	rc = run_tests(tests);

	return rc;
}
