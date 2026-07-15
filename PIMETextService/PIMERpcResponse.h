//
//	Copyright (C) 2026 Yime contributors
//
//	This library is free software; you can redistribute it and/or
//	modify it under the terms of the GNU Library General Public
//	License as published by the Free Software Foundation; either
//	version 2 of the License, or (at your option) any later version.
//

#ifndef _PIME_RPC_RESPONSE_H_
#define _PIME_RPC_RESPONSE_H_

#include <nlohmann/json.hpp>
#include <string>

// Exception-safe helpers for reading backend RPC responses.
//
// IMPORTANT: PIMETextService.dll runs inside arbitrary host processes
// (Explorer, Notepad, Word, ...). An exception thrown by nlohmann::json
// that escapes a TSF COM entry point terminates the host process with
// a 0xc0000409 fail-fast abort. This is exactly what happened when the
// backend was down during profile activation: callRpcMethod() left the
// response as JSON null and handleRpcResponse() called .value() on it,
// which throws type_error.306 ("cannot use value() with null").
//
// Every read of an RPC response MUST therefore be defensive: never
// assume the response is an object, never assume a key exists or has
// the expected type.

namespace PIME {

// Returns true only when the response is a JSON object with "success": true.
// Never throws, no matter what the response looks like (null, wrong types...).
inline bool rpcResponseSucceeded(const nlohmann::json& msg) noexcept {
	if (!msg.is_object()) {
		return false;
	}
	const auto it = msg.find("success");
	return it != msg.end() && it->is_boolean() && it->get<bool>();
}

// Reads the boolean "return" value from a response. Missing key or a
// non-boolean value yields false. Never throws.
inline bool rpcReturnBool(const nlohmann::json& msg) noexcept {
	if (!msg.is_object()) {
		return false;
	}
	const auto it = msg.find("return");
	return it != msg.end() && it->is_boolean() && it->get<bool>();
}

// Reads the numeric command id of a menu item. Menu items coming from the
// backend may carry string ids (e.g. "reverse-lookup") for submenu parents;
// those map to 0 (no direct command). Never throws.
inline unsigned int menuItemCommandId(const nlohmann::json& item) noexcept {
	if (!item.is_object()) {
		return 0;
	}
	const auto it = item.find("id");
	if (it == item.end()) {
		return 0;
	}
	if (it->is_number_unsigned()) {
		return it->get<unsigned int>();
	}
	if (it->is_number_integer()) {
		const auto v = it->get<long long>();
		return v > 0 ? static_cast<unsigned int>(v) : 0u;
	}
	return 0;
}

// Reads the UTF-8 text of a menu item. Missing or non-string text yields
// an empty string. Never throws.
inline std::string menuItemTextUtf8(const nlohmann::json& item) {
	if (!item.is_object()) {
		return std::string();
	}
	const auto it = item.find("text");
	if (it == item.end() || !it->is_string()) {
		return std::string();
	}
	return it->get<std::string>();
}

// Reads an optional boolean attribute of a JSON object. Never throws.
inline bool jsonBoolOr(const nlohmann::json& obj, const char* key, bool defaultValue) noexcept {
	if (!obj.is_object()) {
		return defaultValue;
	}
	const auto it = obj.find(key);
	if (it == obj.end() || !it->is_boolean()) {
		return defaultValue;
	}
	return it->get<bool>();
}

// Reads an optional string attribute of a JSON object. Never throws.
inline std::string jsonStringOr(const nlohmann::json& obj, const char* key, const char* defaultValue) {
	if (!obj.is_object()) {
		return std::string(defaultValue);
	}
	const auto it = obj.find(key);
	if (it == obj.end() || !it->is_string()) {
		return std::string(defaultValue);
	}
	return it->get<std::string>();
}

} // namespace PIME

#endif // _PIME_RPC_RESPONSE_H_
