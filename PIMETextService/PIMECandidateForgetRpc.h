#ifndef PIME_CANDIDATE_FORGET_RPC_H
#define PIME_CANDIDATE_FORGET_RPC_H

#include <windows.h>
#include <nlohmann/json.hpp>

namespace PIME {

inline bool isCandidateForgetShortcut(
	UINT keyCode, bool controlDown, bool altDown) {
	return keyCode == VK_DELETE && controlDown && !altDown;
}

inline void setCandidateForgetRequestIndex(
	nlohmann::json& request, int candidateIndex) {
	if(candidateIndex < 0)
		return;
	auto& data = request["data"];
	if(!data.is_object())
		data = nlohmann::json::object();
	data["candidateIndex"] = candidateIndex;
}

} // namespace PIME

#endif
