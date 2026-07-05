// Regression tests for the host-crash failure path:
//
// Selecting the 音元拼音 profile while the backend is down/restarting used to
// terminate the host process (Explorer/Notepad, exit code 0xc0000409):
// Client::onActivate -> callRpcMethod fails -> response stays JSON null ->
// handleRpcResponse called msg.value("success", ...) on the null response ->
// nlohmann type_error.306 escaped the TSF COM boundary -> abort().
//
// These tests pin the exception-free contract of the response helpers that
// PIMEClient.cpp now uses for every RPC response and menu item.

#include "../PIMERpcResponse.h"

#include <cstdio>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

static int failures = 0;

#define CHECK(expr) \
	do { \
		if (!(expr)) { \
			std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); \
			++failures; \
		} \
	} while (0)

// The concrete crash: RPC failure leaves the response as JSON null.
static void testNullResponseDoesNotThrow() {
	json nullResponse; // exactly what callRpcMethod leaves behind on failure
	try {
		CHECK(!PIME::rpcResponseSucceeded(nullResponse));
		CHECK(!PIME::rpcReturnBool(nullResponse));
	}
	catch (...) {
		std::printf("FAIL: null RPC response must never throw (host would abort)\n");
		++failures;
	}
}

static void testMalformedResponsesDoNotThrow() {
	const json malformed[] = {
		json::parse("[1,2,3]"),
		json::parse("\"plain string\""),
		json::parse("42"),
		json::parse("{\"success\": \"yes\"}"),          // wrong type
		json::parse("{\"success\": true}"),              // missing "return"
		json::parse("{\"success\": true, \"return\": \"x\"}"), // wrong "return" type
		json::parse("{\"seqNum\": null}"),
	};
	for (const auto& msg : malformed) {
		try {
			(void)PIME::rpcResponseSucceeded(msg);
			(void)PIME::rpcReturnBool(msg);
		}
		catch (...) {
			std::printf("FAIL: malformed response threw: %s\n", msg.dump().c_str());
			++failures;
		}
	}

	CHECK(PIME::rpcResponseSucceeded(json::parse("{\"success\": true}")));
	CHECK(!PIME::rpcReturnBool(json::parse("{\"success\": true}")));
	CHECK(PIME::rpcReturnBool(json::parse("{\"success\": true, \"return\": true}")));
	CHECK(!PIME::rpcReturnBool(json::parse("{\"return\": false}")));
}

// Language-bar menus: items may use string ids (submenu parents such as
// "reverse-lookup") next to numeric command ids such as 44 (反查显示 音元拼音).
// item.value("id", 0) used to throw type_error.302 on string ids, killing the
// host when a menu containing them was opened or clicked.
static void testMenuItemsWithMixedIdTypesDoNotThrow() {
	const json menu = json::parse(R"([
		{"id": 44, "text": "音元拼音", "checked": true},
		{"id": "reverse-lookup", "text": "反查显示", "submenu": [{"id": 45, "text": "键位序列"}]},
		{"id": null, "text": "分隔符前"},
		{},
		{"id": -3, "text": "负数 id"},
		{"id": 46, "text": 12345},
		{"id": 47, "text": "正常项", "checked": "not-a-bool", "enabled": 1}
	])");

	try {
		CHECK(PIME::menuItemCommandId(menu[0]) == 44u);
		CHECK(PIME::menuItemTextUtf8(menu[0]) == u8"音元拼音");
		CHECK(PIME::jsonBoolOr(menu[0], "checked", false));

		CHECK(PIME::menuItemCommandId(menu[1]) == 0u); // string id -> no command
		CHECK(PIME::menuItemTextUtf8(menu[1]) == u8"反查显示");

		CHECK(PIME::menuItemCommandId(menu[2]) == 0u);
		CHECK(PIME::menuItemCommandId(menu[3]) == 0u);
		CHECK(PIME::menuItemTextUtf8(menu[3]).empty());
		CHECK(PIME::menuItemCommandId(menu[4]) == 0u); // negative -> no command
		CHECK(PIME::menuItemTextUtf8(menu[5]).empty()); // non-string text
		CHECK(PIME::menuItemCommandId(menu[6]) == 47u);
		CHECK(!PIME::jsonBoolOr(menu[6], "checked", false)); // wrong type -> default
		CHECK(PIME::jsonBoolOr(menu[6], "enabled", true));   // wrong type -> default
	}
	catch (...) {
		std::printf("FAIL: menu item parsing threw (host would abort)\n");
		++failures;
	}
}

static void testJsonStringOr() {
	const json obj = json::parse("{\"id\": \"windows-mode-icon\", \"bad\": 7}");
	CHECK(PIME::jsonStringOr(obj, "id", "") == "windows-mode-icon");
	CHECK(PIME::jsonStringOr(obj, "bad", "d") == "d");
	CHECK(PIME::jsonStringOr(obj, "missing", "d") == "d");
	CHECK(PIME::jsonStringOr(json(), "id", "d") == "d");
}

int main() {
	testNullResponseDoesNotThrow();
	testMalformedResponsesDoNotThrow();
	testMenuItemsWithMixedIdTypesDoNotThrow();
	testJsonStringOr();

	if (failures == 0) {
		std::printf("All PIMERpcResponse tests passed.\n");
		return 0;
	}
	std::printf("%d failure(s).\n", failures);
	return 1;
}
