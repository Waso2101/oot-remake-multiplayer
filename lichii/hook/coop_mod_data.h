// SPDX-License-Identifier: GPL-3.0-or-later
// The mod-data channel's client side (MOD_DATA, 492; docs/protocol.md "Mod data", issue 250 (1)): small
// values a mod gives the other players' copies of the same mod, under keys of its own. Our own values are
// kept here and sent when they change (at most every kSendEveryMs) and again after a reconnect; the server
// keeps everyone's newest, gives them to a joiner and drops a player's when it leaves. The others' values
// are kept by player, mod and key.
#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <tuple>
#include <vector>

#include "coop/protocol/messages.hpp"

namespace coop::host {
class Session;
}
namespace coop::net {
class Client;
struct Event;
}  // namespace coop::net

namespace CoopModData {

using Bytes = std::vector<std::uint8_t>;
inline constexpr std::uint64_t kSendEveryMs = 250;

// The logic, without a network (tests).
class Store {
public:
    // Our value for mod and key ({} clears it); false when the id, key or size is not allowed.
    bool Set(const std::string& mod_id, const std::string& key, Bytes value);
    // A received message or a session event; true when another player's value changed.
    bool OnEvent(const coop::net::Event& event);
    // Our values to send now (each changed one; all of them after a new session), once.
    std::vector<coop::protocol::ModData> TakeSend(std::uint64_t now_ms);
    std::optional<Bytes> Of(std::uint8_t player, const std::string& mod_id, const std::string& key) const;

private:
    using Key = std::tuple<std::string, std::string>;
    std::map<Key, Bytes> ours_;
    std::map<Key, bool> due_;   // ours to send (a cleared one sends an empty value)
    std::map<std::uint8_t, std::map<Key, Bytes>> theirs_;
    std::uint64_t last_send_ms_ = 0;
    bool sent_once_ = false;
};

// The process-wide store, any thread.
bool Set(const std::string& mod_id, const std::string& key, Bytes value);
std::optional<Bytes> Of(std::uint8_t player, const std::string& mod_id, const std::string& key);
// The network thread: each event (coop_hook.cpp's event loop).
void OnEvent(const coop::net::Event& event, coop::net::Client& client);
// Each frame: our changed values out.
void Frame(coop::host::Session* session, std::uint64_t now_ms);

}  // namespace CoopModData
