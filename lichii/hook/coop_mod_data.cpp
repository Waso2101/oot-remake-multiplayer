// SPDX-License-Identifier: GPL-3.0-or-later
#include "coop_mod_data.h"

#include <mutex>
#include <utility>

#include "coop/host/session.hpp"
#include "coop/net/client.hpp"

#ifdef LICHII_COOP
#include "common/logging.h"
#endif

namespace CoopModData {

using coop::net::EventKind;
using coop::protocol::ModData;

namespace {

bool ValidKey(const std::string& key) {
    if (key.empty() || key.size() > coop::protocol::kMaxModDataKeyChars) {
        return false;
    }
    for (const char c : key) {
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) {
            return false;
        }
    }
    return true;
}

bool ValidModId(const std::string& id) {
    if (id.empty() || id.size() > coop::protocol::kMaxModIdChars) {
        return false;
    }
    for (const char c : id) {
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-')) {
            return false;
        }
    }
    return true;
}

int HexDigit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

}  // namespace

bool Store::Set(const std::string& mod_id, const std::string& key, Bytes value) {
    if (!ValidModId(mod_id) || !ValidKey(key) || value.size() > coop::protocol::kMaxModDataValueBytes) {
        return false;
    }
    const Key k{mod_id, key};
    const auto it = ours_.find(k);
    if (value.empty()) {
        if (it != ours_.end()) {
            ours_.erase(it);
            due_[k] = true;
        }
        return true;
    }
    if (it == ours_.end() || it->second != value) {
        ours_[k] = std::move(value);
        due_[k] = true;
    }
    return true;
}

bool Store::OnEvent(const coop::net::Event& event) {
    switch (event.kind) {
    case EventKind::welcomed:
    case EventKind::reconnected: {
        // A new session, or a server that may have lost us: the others' values come again from the
        // server, ours go out again.
        const bool had = !theirs_.empty();
        theirs_.clear();
        for (const auto& [k, v] : ours_) {
            due_[k] = true;
        }
        return had;
    }
    case EventKind::player_left:
        return theirs_.erase(event.player) != 0;
    case EventKind::message:
        if (const auto* d = std::get_if<ModData>(&event.message);
            d != nullptr && d->player_number != coop::protocol::kPlayerSelf) {
            auto& values = theirs_[d->player_number];
            const Key k{d->mod_id, d->key};
            if (d->value.empty()) {
                return values.erase(k) != 0;
            }
            const auto it = values.find(k);
            if (it != values.end() && it->second == d->value) {
                return false;
            }
            values[k] = d->value;
            return true;
        }
        return false;
    default:
        return false;
    }
}

std::vector<ModData> Store::TakeSend(std::uint64_t now_ms) {
    std::vector<ModData> out;
    if (due_.empty() || (sent_once_ && now_ms - last_send_ms_ < kSendEveryMs)) {
        return out;
    }
    for (const auto& [k, due] : due_) {
        if (!due) {
            continue;
        }
        ModData d;
        d.mod_id = std::get<0>(k);
        d.key = std::get<1>(k);
        if (const auto it = ours_.find(k); it != ours_.end()) {
            d.value = it->second;
        }
        out.push_back(std::move(d));
    }
    due_.clear();
    last_send_ms_ = now_ms;
    sent_once_ = true;
    return out;
}

std::optional<Bytes> Store::Of(std::uint8_t player, const std::string& mod_id, const std::string& key) const {
    const auto p = theirs_.find(player);
    if (p == theirs_.end()) {
        return std::nullopt;
    }
    const auto it = p->second.find(Key{mod_id, key});
    if (it == p->second.end()) {
        return std::nullopt;
    }
    return it->second;
}

namespace {
std::mutex g_mutex;
Store g_store;   // guarded
bool g_connected = false;   // guarded: sends wait for a session
}  // namespace

bool Set(const std::string& mod_id, const std::string& key, Bytes value) {
    std::lock_guard lock(g_mutex);
    return g_store.Set(mod_id, key, std::move(value));
}

std::optional<Bytes> Of(std::uint8_t player, const std::string& mod_id, const std::string& key) {
    std::lock_guard lock(g_mutex);
    return g_store.Of(player, mod_id, key);
}

void OnEvent(const coop::net::Event& event, coop::net::Client& client) {
    (void)client;
    bool changed = false;
    {
        std::lock_guard lock(g_mutex);
        changed = g_store.OnEvent(event);
        if (event.kind == EventKind::welcomed || event.kind == EventKind::reconnected) {
            g_connected = true;
        } else if (event.kind == EventKind::disconnected || event.kind == EventKind::refused) {
            g_connected = false;
        }
    }
#ifdef LICHII_COOP
    if (const auto* d = std::get_if<ModData>(&event.message);
        changed && event.kind == EventKind::message && d != nullptr) {
        if (d->mod_id == "coop" && d->key == "skin") {
            const auto skin = SkinOf(d->value);
            LOG_INFO(Core, "coop: skin: P{} wears {}", d->player_number,
                     skin && !skin->first.empty() ? skin->first : std::string("Link"));
        } else {
            LOG_INFO(Core, "coop: mod data: P{} {}/{} ({} bytes)", d->player_number, d->mod_id, d->key,
                     d->value.size());
        }
    }
#else
    (void)changed;
#endif
}

void Frame(coop::host::Session* session, std::uint64_t now_ms) {
    if (session == nullptr) {
        return;
    }
    std::vector<ModData> send;
    {
        std::lock_guard lock(g_mutex);
        if (!g_connected) {
            return;
        }
        send = g_store.TakeSend(now_ms);
    }
    if (send.empty()) {
        return;
    }
    session->with_client([&](coop::net::Client& c) {
        for (const ModData& d : send) {
            c.send(d);
        }
    });
#ifdef LICHII_COOP
    for (const ModData& d : send) {
        if (d.mod_id == "coop" && d.key == "skin") {
            const auto skin = SkinOf(d.value);
            LOG_INFO(Core, "coop: skin: sent: we wear {}", skin && !skin->first.empty() ? skin->first : std::string("Link"));
        }
    }
#endif
}

Bytes SkinValue(const std::string& id, const std::string& sha256_hex) {
    if (id.empty() || sha256_hex.size() != 64) {
        return {};
    }
    Bytes out(id.begin(), id.end());
    out.push_back(0);
    for (std::size_t i = 0; i < 64; i += 2) {
        const int hi = HexDigit(sha256_hex[i]), lo = HexDigit(sha256_hex[i + 1]);
        if (hi < 0 || lo < 0) {
            return {};
        }
        out.push_back(static_cast<std::uint8_t>(hi * 16 + lo));
    }
    return out.size() <= coop::protocol::kMaxModDataValueBytes ? out : Bytes{};
}

std::optional<std::pair<std::string, std::string>> SkinOf(const Bytes& value) {
    if (value.empty()) {
        return std::pair<std::string, std::string>{};
    }
    std::size_t zero = 0;
    while (zero < value.size() && value[zero] != 0) {
        ++zero;
    }
    if (zero == 0 || zero > 20 || value.size() != zero + 1 + 32) {
        return std::nullopt;
    }
    std::string id(value.begin(), value.begin() + static_cast<std::ptrdiff_t>(zero));
    for (const char c : id) {
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) {
            return std::nullopt;
        }
    }
    static const char* kHex = "0123456789abcdef";
    std::string hex;
    for (std::size_t i = zero + 1; i < value.size(); ++i) {
        hex.push_back(kHex[value[i] >> 4]);
        hex.push_back(kHex[value[i] & 15]);
    }
    return std::pair<std::string, std::string>{std::move(id), std::move(hex)};
}

}  // namespace CoopModData
