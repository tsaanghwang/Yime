#pragma once
#include <nlohmann/json.hpp>
#include <set>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>
namespace yime::activated {
inline nlohmann::json ParseConfig(const std::string& text){
 using json=nlohmann::json;
 if(text.empty()||text.size()>16384)throw std::runtime_error("config-bound");
 bool duplicate=false;std::vector<std::set<std::string>> keys;
 auto value=json::parse(text,[&](int depth,json::parse_event_t event,json& parsed){
  if(depth>8)throw std::runtime_error("config-depth");
  if(event==json::parse_event_t::object_start)keys.emplace_back();
  if(event==json::parse_event_t::key){if(keys.empty()||!keys.back().insert(parsed.get<std::string>()).second)duplicate=true;}
  if(event==json::parse_event_t::object_end){if(!keys.empty())keys.pop_back();}
  return true;
 });
 const std::set<std::string> names{"schema","hostPID","brokerPID","brokerImage","brokerSHA256","pipe","code"};
 if(duplicate||!value.is_object()||value.size()!=names.size())throw std::runtime_error("config-schema");
 for(auto it=value.begin();it!=value.end();++it)if(!names.count(it.key()))throw std::runtime_error("config-field");
 if(value.at("schema")!="activated-loop-config-v1")throw std::runtime_error("config-version");
 for(const char* field:{"hostPID","brokerPID"})if(!value.at(field).is_number_unsigned()||value.at(field).get<std::uint64_t>()==0||value.at(field).get<std::uint64_t>()>0xffffffffULL)throw std::runtime_error("config-pid");
 for(const char* field:{"brokerImage","brokerSHA256","pipe","code"})if(!value.at(field).is_string()||value.at(field).get_ref<const std::string&>().find('\0')!=std::string::npos)throw std::runtime_error("config-string");
 const auto hash=value.at("brokerSHA256").get<std::string>();
 if(hash.size()!=64||hash.find_first_not_of("0123456789abcdef")!=std::string::npos)throw std::runtime_error("config-hash");
 const auto image=value.at("brokerImage").get<std::string>();
 if(image.size()<4||image.size()>4096||image[1]!=':'||image[2]!='\\'||image.find(':',2)!=std::string::npos)throw std::runtime_error("config-image");
 const auto pipe=value.at("pipe").get<std::string>();const std::string prefix="\\\\.\\pipe\\YimeBroker.18uTouch.v1.";
 if(pipe.size()<=prefix.size()||pipe.size()>prefix.size()+96||pipe.compare(0,prefix.size(),prefix)!=0||pipe.substr(prefix.size()).find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")!=std::string::npos)throw std::runtime_error("config-pipe");
 const auto code=value.at("code").get<std::string>();
 if(code.empty()||code.size()>128)throw std::runtime_error("config-code");
 for(unsigned char c:code)if(c<33||c>126)throw std::runtime_error("config-code");
 return value;
}
}
