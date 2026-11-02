#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace yime::stage1 {
enum class ResidueShape { Absent, Empty, DisabledOnly, Unexpected };
struct ResidueObservation {
 ResidueShape shape=ResidueShape::Unexpected;
 std::uint64_t revision=0;
 bool operator==(const ResidueObservation& b)const{return shape==b.shape&&revision==b.revision;}
};
struct ResidueTarget { std::string id; bool absentBefore=false,attemptRecorded=false,allowDisabled=false; };
// Backend owns the fixed path allowlist. No recursion, retries or compensation.
// Rechecks reduce races, but are NOT an atomic compare-and-delete guarantee.
template<class Backend>
void CleanNewResidue(unsigned ledgerVersion,const std::vector<ResidueTarget>& targets,Backend& backend){
 if(ledgerVersion!=4)throw std::runtime_error("legacy-ledger-no-item-provenance");
 for(const auto& target:targets) {
  if(!target.absentBefore)throw std::runtime_error("missing-before-absence");
 }
 for(const auto& target:targets) {
  backend.checkOwner();
  const auto before=backend.observe(target.id);
  if(before.shape==ResidueShape::Absent){backend.record(target.id,"already-absent");continue;}
  if(!target.attemptRecorded)throw std::runtime_error("item-write-not-recorded");
  if(before.shape!=ResidueShape::Empty && !(target.allowDisabled&&before.shape==ResidueShape::DisabledOnly))
   throw std::runtime_error("unexpected-residue-shape");
  backend.checkOwner();
  if(!(before==backend.observe(target.id)))throw std::runtime_error("residue-changed-before-delete");
  backend.eraseOne(target.id); // deletes exactly this key, never a subtree
  if(backend.observe(target.id).shape!=ResidueShape::Absent)throw std::runtime_error("residue-present-after-delete");
  backend.record(target.id,"deleted-and-absent");
 }
}
}
