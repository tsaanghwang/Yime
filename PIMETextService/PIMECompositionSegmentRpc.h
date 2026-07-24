#ifndef PIME_COMPOSITION_SEGMENT_RPC_H
#define PIME_COMPOSITION_SEGMENT_RPC_H

#include <nlohmann/json.hpp>
#include <string>
#include <utility>
#include <vector>

namespace PIME {

struct CompositionSegmentPayload {
	int start;
	int end;
	std::string code;
	std::string text;
	bool active;
};

inline std::vector<CompositionSegmentPayload> compositionSegmentsFromResponse(
	const nlohmann::json& response) {
	std::vector<CompositionSegmentPayload> segments;
	if(!response.is_object() || !response.contains("compositionSegments"))
		return segments;
	const auto& values = response["compositionSegments"];
	if(!values.is_array())
		return segments;
	for(const auto& value : values) {
		if(!value.is_object() || !value.contains("start") ||
			!value.contains("end") || !value.contains("code") ||
			!value.contains("text") || !value.contains("active"))
			continue;
		const auto& start = value["start"];
		const auto& end = value["end"];
		const auto& code = value["code"];
		const auto& text = value["text"];
		const auto& active = value["active"];
		if(!start.is_number_integer() || !end.is_number_integer() ||
			!code.is_string() || !text.is_string() || !active.is_boolean())
			continue;
		CompositionSegmentPayload segment = {
			start.get<int>(), end.get<int>(), code.get<std::string>(),
			text.get<std::string>(), active.get<bool>(),
		};
		if(segment.start >= 0 && segment.end > segment.start)
			segments.push_back(std::move(segment));
	}
	return segments;
}

inline void setCompositionSegmentRequestPosition(
	nlohmann::json& request, int start, int end) {
	request["cursorPos"] = start;
	request["selEnd"] = end;
}

} // namespace PIME

#endif
