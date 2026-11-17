// SPDX-License-Identifier: GPL-3.0-or-later
// The puppets' settings from the variables, the same on the emulator and
// Hookshot (lichii/hook/coop_puppet_config.h).
#include <doctest/doctest.h>

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "coop_puppet_config.h"

namespace {

CoopPuppet::PlannerSettings From(const std::map<std::string, std::string>& vars, bool pack_green,
                                 std::vector<std::string>* log = nullptr, int* asked = nullptr) {
    return CoopPuppetConfig::Settings(
        [&](const char* name) {
            const auto it = vars.find(name);
            return it == vars.end() ? std::string() : it->second;
        },
        [&] {
            if (asked != nullptr) ++*asked;
            return pack_green;
        },
        log);
}

}  // namespace

TEST_CASE("puppet config: nothing set gives coloured tunics and no test puppet") {
    int asked = 0;
    const auto s = From({}, false, nullptr, &asked);
    CHECK(s.tunics);
    CHECK_FALSE(s.green_puppet);  // (this pack has no green puppets)
    CHECK_FALSE(s.debug);
    CHECK_FALSE(s.debug_anim);
    CHECK(s.actor.empty());
    CHECK(asked == 1);
}

TEST_CASE("puppet config: LICHII_COOP_TUNICS=0 or off puts everyone in green") {
    CHECK_FALSE(From({{"LICHII_COOP_TUNICS", "0"}}, false).tunics);
    CHECK_FALSE(From({{"LICHII_COOP_TUNICS", "off"}}, false).tunics);
    CHECK(From({{"LICHII_COOP_TUNICS", "1"}}, false).tunics);
    std::vector<std::string> log;
    From({{"LICHII_COOP_TUNICS", "0"}}, false, &log);
    REQUIRE(!log.empty());
    CHECK(log.back().find("tunics off") != std::string::npos);
}

// Player report 47 (0.11.0): the plain puppet's model is your own Link's
// colour-agree copy at every start, green or none too, so a pack with the
// green puppets gives them to green players whatever your own Link wears.
TEST_CASE("puppet config: a pack with green puppets gives them to green players whatever your own colour") {
    for (const char* self : {"", "green", "blue"}) {
        CAPTURE(self);
        std::vector<std::string> log;
        int asked = 0;
        const auto s = From({{"LICHII_COOP_SELF_TUNIC", self}}, true, &log, &asked);
        CHECK(s.green_puppet);
        CHECK(asked == 1);
        REQUIRE(log.size() == 2);
        CHECK(log[0] == std::string("coop: your Link wears ") + (*self ? self : "green") +
                            " at the start; green players get CoopPuppet_<Age>_Green");
    }
    // An old pack: the plain puppet, and the log says to make the pack again.
    std::vector<std::string> log;
    const auto s = From({{"LICHII_COOP_SELF_TUNIC", "red"}}, false, &log);
    CHECK_FALSE(s.green_puppet);
    CHECK(log[0].find("make it again") != std::string::npos);
}

TEST_CASE("puppet config: actor, test puppet and animation log switches") {
    const auto s = From({{"LICHII_COOP_PUPPET_ACTOR", "CoopPuppet_Adult"},
                         {"LICHII_COOP_TEST_PUPPET", "1"},
                         {"LICHII_COOP_DEBUG_ANIM", "1"}},
                        false);
    CHECK(s.actor == "CoopPuppet_Adult");
    CHECK(s.debug);
    CHECK(s.debug_anim);
    CHECK_FALSE(From({{"LICHII_COOP_TEST_PUPPET", "0"}}, false).debug);
}

TEST_CASE("puppet config: the native player test is off unless asked for") {
    CHECK_FALSE(From({}, false).native_player);
    CHECK_FALSE(From({{"LICHII_COOP_NATIVE_PLAYER", "0"}}, false).native_player);
    std::vector<std::string> log;
    CHECK(From({{"LICHII_COOP_NATIVE_PLAYER", "1"}}, false, &log).native_player);
    CHECK(log.back().find("NATIVE PLAYER TEST") != std::string::npos);
}

TEST_CASE("puppet config: a pack without tunic puppets turns the tunics off (Hookshot proof 3)") {
    const auto with = [](std::optional<bool> has, std::vector<std::string>* log = nullptr, int* asked = nullptr,
                         std::map<std::string, std::string> vars = {}) {
        return CoopPuppetConfig::Settings(
            [&](const char* name) {
                const auto it = vars.find(name);
                return it == vars.end() ? std::string() : it->second;
            },
            [] { return false; }, log,
            [&]() -> std::optional<bool> {
                if (asked != nullptr) ++*asked;
                return has;
            });
    };
    // The pairs' pack from before the tunics: plain puppets only, and the log says why.
    std::vector<std::string> log;
    CHECK_FALSE(with(false, &log).tunics);
    REQUIRE(log.size() == 2);
    CHECK(log[0].find("no tunic colours") != std::string::npos);
    CHECK(log[0].find("make-puppet-pack") != std::string::npos);
    CHECK(log[1].find(", tunics off (the pack has none)") != std::string::npos);
    // A pack with them, or no manifest found: as before.
    CHECK(with(true).tunics);
    CHECK(with(std::nullopt).tunics);
    // LICHII_COOP_TUNICS=0 wins and the pack is not read for it.
    int asked = 0;
    log.clear();
    CHECK_FALSE(with(true, &log, &asked, {{"LICHII_COOP_TUNICS", "0"}}).tunics);
    CHECK(asked == 0);
    CHECK(log.back().find("(LICHII_COOP_TUNICS=0)") != std::string::npos);
}

TEST_CASE("puppet config: the manifest names tunic puppets or only the plain ones") {
    // Lines as tools/puppet_pack writes them (coop_puppet.json "actors").
    const std::string plain = R"({"actors": [{"actor": "CoopPuppet_Child", "pack": "Pack/Actor/CoopPuppet_Child.pack.zs",
        "members": ["Actor/CoopPuppet_Child.engine__actor__ActorParam.bgyml"]}, {"actor": "CoopPuppet_Adult"}]})";
    const std::string tunics = R"({"actors": [{"actor": "CoopPuppet_Child"}, {"actor": "CoopPuppet_Child_Blue"},
        {"actor": "CoopPuppet_Adult_Blue"}]})";
    CHECK_FALSE(CoopPuppet::PackHasTunicPuppets(plain));
    CHECK(CoopPuppet::PackHasTunicPuppets(tunics));
    CHECK(CoopPuppet::PackHasTunicPuppets(R"({"actor": "CoopPuppet_Adult_Red"})"));
    CHECK_FALSE(CoopPuppet::PackHasTunicPuppets(""));
}

TEST_CASE("puppet config: the pack's item copies, unless LICHII_COOP_LOOK_ITEMS=0") {
    const auto look = [] {
        CoopPuppet::LookItems items;
        items.actors = {"Weapon_Shield_Hylian"};
        items.copies = 8;
        return items;
    };
    const auto env = [](std::string value) {
        return [value](const char* name) { return std::string(name) == "LICHII_COOP_LOOK_ITEMS" ? value : std::string(); };
    };
    std::vector<std::string> log;
    auto s = CoopPuppetConfig::Settings(env(""), [] { return false; }, &log, {}, look);
    CHECK(s.look_copies == 8);
    CHECK(s.look_items == std::vector<std::string>{"Weapon_Shield_Hylian"});
    CHECK(std::any_of(log.begin(), log.end(), [](const std::string& l) { return l.find("coloured items") != std::string::npos; }));
    s = CoopPuppetConfig::Settings(env("0"), [] { return false; }, nullptr, {}, look);
    CHECK(s.look_copies == 0);
    CHECK(s.look_items.empty());
    s = CoopPuppetConfig::Settings(env(""), [] { return false; }, nullptr);
    CHECK(s.look_copies == 0);
}

TEST_CASE("puppet config: LICHII_COOP_SEE_LINK sees everyone as Link") {
    const auto env = [](std::string value) {
        return [value](const char* name) { return std::string(name) == "LICHII_COOP_SEE_LINK" ? value : std::string(); };
    };
    const auto green = [] { return false; };
    CHECK(CoopPuppetConfig::Settings(env("1"), green, nullptr).everyone_link);
    CHECK_FALSE(CoopPuppetConfig::Settings(env("0"), green, nullptr).everyone_link);
    CHECK_FALSE(CoopPuppetConfig::Settings(env(""), green, nullptr).everyone_link);
}
