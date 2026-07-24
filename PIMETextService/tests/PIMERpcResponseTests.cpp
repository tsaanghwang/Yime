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
#include "../PIMEKeyRouting.h"
#include "../PIMECompositionSegmentRpc.h"
#include "../PIMEProcessValidation.h"
#include "../PIMEUiPolicy.h"
#include "../../libIME2/src/CandidateWindowClickPolicy.h"
#include "../../libIME2/src/CompositionSegmentStrip.h"

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

static void testUiLessCandidateWindowPolicy() {
	CHECK(PIME::shouldShowOwnedCandidateWindow(false, FALSE));
	CHECK(PIME::shouldShowOwnedCandidateWindow(false, TRUE));
	CHECK(!PIME::shouldShowOwnedCandidateWindow(true, FALSE));
	CHECK(PIME::shouldShowOwnedCandidateWindow(true, TRUE));
}

static void testCandidateWindowKeyRoutingPreservesModifiedNavigation() {
	const UINT localCandidateKeys[] = {
		VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_RETURN, VK_SPACE,
	};
	for (const UINT keyCode : localCandidateKeys) {
		CHECK(PIME::shouldCandidateWindowHandleKey(keyCode, false));
	}

	CHECK(!PIME::shouldCandidateWindowHandleKey(VK_LEFT, true));
	CHECK(!PIME::shouldCandidateWindowHandleKey(VK_RIGHT, true));
	CHECK(PIME::shouldCandidateWindowHandleKey(VK_UP, true));
	CHECK(PIME::shouldCandidateWindowHandleKey(VK_DOWN, true));
	CHECK(PIME::shouldCandidateWindowHandleKey(VK_RETURN, true));
	CHECK(PIME::shouldCandidateWindowHandleKey(VK_SPACE, true));

	for (UINT keyCode = '0'; keyCode <= '9'; ++keyCode) {
		CHECK(!PIME::shouldCandidateWindowHandleKey(keyCode, false));
		CHECK(!PIME::shouldCandidateWindowHandleKey(keyCode, true));
	}
}

static void testOwnedSegmentStripHostCallbackPath() {
	const auto segment = Ime::candidateWindowClickTarget(2, -1);
	CHECK(segment.kind == Ime::CandidateWindowClickKind::CompositionSegment);
	CHECK(segment.index == 2);

	// The strip must win even if future layout changes accidentally overlap a
	// candidate rectangle; this prevents committing a candidate on segment click.
	const auto overlap = Ime::candidateWindowClickTarget(1, 4);
	CHECK(overlap.kind == Ime::CandidateWindowClickKind::CompositionSegment);
	CHECK(overlap.index == 1);

	json request = {{"method", "selectCompositionSegment"}};
	PIME::setCompositionSegmentRequestPosition(request, segment.index, 4);
	CHECK(request["method"] == "selectCompositionSegment");
	CHECK(request["cursorPos"] == 2);
	CHECK(request["selEnd"] == 4);
}

static void testStructuredCompositionSegmentsAreValidated() {
	const json response = json::parse(R"({
		"compositionSegments": [
			{"start": 0, "end": 4, "code": "bjjj", "text": "幅", "active": false},
			{"start": 5, "end": 9, "code": "bjjj", "text": "幅", "active": true},
			{"start": -1, "end": 2, "code": "bad", "text": "坏", "active": false},
			{"start": "x", "end": 3, "code": "bad", "text": "坏", "active": false}
		]
	})");
	const auto segments = PIME::compositionSegmentsFromResponse(response);
	CHECK(segments.size() == 2);
	CHECK(segments[0].start == 0);
	CHECK(segments[0].end == 4);
	CHECK(segments[0].code == "bjjj");
	CHECK(segments[0].text == u8"幅");
	CHECK(!segments[0].active);
	CHECK(segments[1].active);
	CHECK(PIME::compositionSegmentsFromResponse(json()).empty());
}

static void testCompositionStripUsesCodePointOffsets() {
	const std::wstring text = L"A\U0001F600B";
	const auto spans = Ime::compositionCodePointSpans(text);
	CHECK(spans.size() == 3);
	CHECK(spans[0].utf16Length == 1);
	CHECK(spans[1].utf16Length == 2);
	CHECK(spans[2].utf16Length == 1);

	int start = -3;
	int end = 99;
	Ime::normalizeCompositionSegmentRange(3, start, end);
	CHECK(start == 0);
	CHECK(end == 3);
}

static void testCandidateFontSizeIsBounded() {
	CHECK(PIME::normalizeCandidateFontSize(-1) == PIME::kMinimumCandidateFontSize);
	CHECK(PIME::normalizeCandidateFontSize(12) == 12);
	CHECK(PIME::normalizeCandidateFontSize(999) == PIME::kMaximumCandidateFontSize);
}

static void testPopupAnchorStaysInsideWorkArea() {
	const RECT workArea = { 0, 0, 1920, 1040 };
	const RECT nearBottomRight = { 1900, 1010, 1910, 1030 };
	const SIZE popup = { 300, 200 };
	const POINT point = PIME::popupAnchorInWorkArea(nearBottomRight, popup, workArea);
	CHECK(point.x == 1620);
	CHECK(point.y == 810);

	const RECT nearTopLeft = { -50, -20, -40, -10 };
	const POINT clamped = PIME::popupAnchorInWorkArea(nearTopLeft, popup, workArea);
	CHECK(clamped.x == 0);
	CHECK(clamped.y == 0);
}

static void testLauncherExecutableValidation() {
	CHECK(PIME::isExpectedLauncherExecutablePath(LR"(C:\Program Files (x86)\YIME\PIMELauncher.exe)"));
	CHECK(PIME::isExpectedLauncherExecutablePath(LR"(C:\dev\Yime\build\PIMELauncher\pimelauncher.EXE)"));
	CHECK(!PIME::isExpectedLauncherExecutablePath(LR"(C:\Windows\System32\cmd.exe)"));
	CHECK(!PIME::isExpectedLauncherExecutablePath(L"PIMELauncher.exe.bak"));
	CHECK(PIME::canFallbackToPipeAclAfterProcessQueryFailure(ERROR_ACCESS_DENIED));
	CHECK(!PIME::canFallbackToPipeAclAfterProcessQueryFailure(ERROR_INVALID_HANDLE));
	CHECK(!PIME::canFallbackToPipeAclAfterProcessQueryFailure(ERROR_INSUFFICIENT_BUFFER));
}

int main() {
	testNullResponseDoesNotThrow();
	testMalformedResponsesDoNotThrow();
	testMenuItemsWithMixedIdTypesDoNotThrow();
	testJsonStringOr();
	testUiLessCandidateWindowPolicy();
	testCandidateWindowKeyRoutingPreservesModifiedNavigation();
	testOwnedSegmentStripHostCallbackPath();
	testStructuredCompositionSegmentsAreValidated();
	testCompositionStripUsesCodePointOffsets();
	testCandidateFontSizeIsBounded();
	testPopupAnchorStaysInsideWorkArea();
	testLauncherExecutableValidation();

	if (failures == 0) {
		std::printf("All PIMERpcResponse tests passed.\n");
		return 0;
	}
	std::printf("%d failure(s).\n", failures);
	return 1;
}
