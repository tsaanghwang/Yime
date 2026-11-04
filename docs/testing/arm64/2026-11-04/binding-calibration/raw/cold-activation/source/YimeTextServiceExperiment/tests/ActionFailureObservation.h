#pragma once
#include <cstdint>
#include <sstream>
#include <string_view>
namespace yimeactionfailure {
enum class Type { Missing, Null, Boolean, String, Number, Array, Object };
enum class Response { Missing, Malformed, Object, NonObject };
enum class Action { Input, Select };
struct Field { Type type=Type::Missing; bool boolean=false; std::string_view text{}; };
struct Evidence {
    uint32_t hresult=0;
    Action action=Action::Input;
    bool wmQuit=false;
    Response response=Response::Missing;
    Field ok,outcome,localEditOutcome,retryAllowed;
};
inline const char* TypeName(Type type) noexcept {
    switch(type){case Type::Missing:return "missing";case Type::Null:return "null";case Type::Boolean:return "boolean";case Type::String:return "string";case Type::Number:return "number";case Type::Array:return "array";case Type::Object:return "object";}return "invalid";
}
inline const char* ResponseName(Response response) noexcept {
    switch(response){case Response::Missing:return "missing";case Response::Malformed:return "malformed";case Response::Object:return "object";case Response::NonObject:return "non-object";}return "invalid";
}
inline const char* Outcome(std::string_view text) noexcept {
    if(text=="applied")return "applied";
    if(text=="failed")return "failed";
    if(text=="unknown")return "unknown";
    if(text=="pending")return "pending";
    if(text=="not-attempted")return "not-attempted";
    if(text=="not-applied")return "not-applied";
    return "unrecognized"; // Never echo arbitrary response strings.
}
inline void WriteField(std::ostream& out,const Field& field,bool outcome) {
    out<<"{\"type\":\""<<TypeName(field.type)<<"\",\"value\":";
    if(!outcome&&field.type==Type::Boolean)out<<(field.boolean?"true":"false");
    else if(outcome&&field.type==Type::String)out<<'"'<<Outcome(field.text)<<'"';
    else out<<"null";
    out<<'}';
}
// Production uses this same bounded, fixed-field serializer and exception shield.
// Its sink can fail without replacing the original HRESULT/first failure.
template<class Sink> void Emit(const Evidence& evidence,Sink&& sink) noexcept {
    try {
        std::ostringstream out;
        out<<"{\"kind\":\"host-action-failure\",\"action\":\""<<(evidence.action==Action::Input?"input":"select")
           <<"\",\"hresult\":"<<evidence.hresult<<",\"abortSource\":\""<<(evidence.wmQuit?"wm-quit":evidence.hresult==0x80004004u?"route":"not-e-abort")
           <<"\",\"response\":\""<<ResponseName(evidence.response)<<"\",\"ok\":";
        WriteField(out,evidence.ok,false);out<<",\"outcome\":";WriteField(out,evidence.outcome,true);
        out<<",\"localEditOutcome\":";WriteField(out,evidence.localEditOutcome,true);
        out<<",\"retryAllowed\":";WriteField(out,evidence.retryAllowed,false);out<<"}\n";
        sink(out.str());
    }catch(...){/* Preserve the caller's original failure. */}
}
}
