#!/usr/bin/env python3
"""
Single source of truth for the Ballet Diary movement library.

Run:  python3 backend/scripts/build_movements.py
It validates every movement and writes:
  backend/data/movements.json
  ios/BalletDairy/Resources/movements.json

Animation model
---------------
Each movement animates the 3D dancer with keyframes. A keyframe composes three
named pose parts that live in the iOS app (Features/Dancer/PoseLibrary.swift):

  l     legs pose   (also decides support: both feet / one foot / in the air)
  a     arms pose   (default "bras_bas")
  t     torso pose  (default "neutral")
  d     seconds to travel from the previous key to this one
  yaw   absolute body rotation in degrees (turns accumulate: 360, 720 ...)
  lift  extra height in metres (jumps; air poses have a sensible default)
  dx    sideways travel in metres (+ = dancer's left)
  dz    forward travel in metres (+ = towards the audience)
  m     mirror the whole key (work on the other leg)

The cycle loops back to the first key using the first key's `d`.
The working leg is the dancer's RIGHT leg; at the barre the LEFT hand holds it.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

LEGS = {
    "first", "second", "third", "fourth", "fifth",
    "first_demi", "first_grand", "second_demi", "second_grand", "fourth_demi", "fifth_demi",
    "fourth_lunge", "first_releve", "second_releve", "fifth_releve", "sous_sus",
    "tendu_front", "tendu_side", "tendu_back", "tendu_front_plie", "tendu_back_plie", "tendu_side_plie",
    "degage_front", "degage_side", "degage_back",
    "coupe_front", "coupe_back", "coupe_flex", "coupe_releve", "frappe_side", "frappe_front",
    "fondu_coupe", "fondu_front", "fondu_side", "fondu_back",
    "retire", "retire_releve", "retire_plie",
    "developpe_front", "developpe_side", "developpe_back",
    "attitude_front", "attitude_back", "attitude_back_releve",
    "arabesque", "arabesque_releve", "arabesque_plie", "penche_leg",
    "battement_front", "battement_side", "battement_back",
    "rja_side", "rja_in", "seconde_plie", "seconde_releve",
    "air_first", "air_fifth", "air_second", "air_split", "air_saut_de_chat", "air_cabriole",
    "air_pas_de_chat", "air_sissonne", "air_jete", "air_arabesque", "air_attitude",
    "air_ballonne", "air_tour", "air_biche",
}
ARMS = {
    "bras_bas", "first", "second", "third", "fourth", "fifth", "allonge", "demi_second",
    "arabesque1", "arabesque2", "barre", "barre_bas", "barre_first", "barre_fifth", "reverence",
}
TORSO = {
    "neutral", "cambre_back", "cambre_forward", "cambre_side", "arabesque_lean", "penche",
    "epaulement_r", "epaulement_l", "bow",
}
MUSCLES = {
    "glutes", "deep_rotators", "quadriceps", "hamstrings", "adductors", "hip_flexors",
    "calves", "tibialis", "foot_intrinsics", "core", "obliques", "erector_spinae",
    "lats", "deltoids", "trapezius", "arms",
}
CATEGORIES = [
    ("positions", "Positions", "The alphabet of ballet: where the feet live."),
    ("port_de_bras", "Port de bras", "Carriage of the arms, head and upper body."),
    ("barre", "Barre", "Warm-up vocabulary built at the barre."),
    ("center", "Centre & Adagio", "Slow, sustained balance and line in the centre."),
    ("turns", "Turns", "Pirouettes, spins and travelling turns."),
    ("petit_allegro", "Petit allegro", "Small, quick, buoyant jumps."),
    ("grand_allegro", "Grand allegro", "Big travelling leaps that cover the floor."),
    ("linking", "Linking steps", "Steps that connect, travel and breathe."),
    ("pointe", "Pointe", "Vocabulary on the tips of the toes."),
]


def K(l, a="bras_bas", t="neutral", d=0.6, **kw):
    key = {"l": l, "a": a, "t": t, "d": d}
    key.update(kw)
    return key


M: list[dict] = []


def mv(id, name, english, category, level, description, cues, primary, secondary, keys, hero=None, aka=None):
    if hero is None:
        hero = max(range(len(keys)), key=lambda i: 0 if keys[i]["l"] in ("first", "fifth", "third", "second") else 1)
    M.append({
        "id": id, "name": name, "english": english, "category": category, "level": level,
        "description": description, "cues": cues,
        "muscles": {"primary": primary, "secondary": secondary},
        "animation": {"keys": keys, "hero": hero},
        **({"aka": aka} if aka else {}),
    })


TURNOUT = ["deep_rotators", "adductors"]
LEG_LINE = ["quadriceps", "calves", "foot_intrinsics"]

# ───────────────────────────── Positions ─────────────────────────────
mv("first_position", "Première position", "First position", "positions", 1,
   "Heels together, legs rotated out from the hips so the feet form a wide, even line.",
   ["Rotate from the top of the thigh, not the knees", "Weight over the balls of the feet", "Long spine, shoulders down"],
   TURNOUT, ["glutes", "core", "quadriceps"],
   [K("first", d=1.0), K("first", "first", d=1.0), K("first", "second", d=1.0)], hero=0)
mv("second_position", "Seconde position", "Second position", "positions", 1,
   "Feet turned out and apart, about one and a half foot-lengths between the heels.",
   ["Even weight on both feet", "Knees over toes", "Lengthen up through the crown"],
   TURNOUT, ["glutes", "core"],
   [K("second", d=1.0), K("second", "second", d=1.0)], hero=1)
mv("third_position", "Troisième position", "Third position", "positions", 1,
   "The heel of the front foot sits against the middle of the back foot — the gentle step towards fifth.",
   ["Cross only as far as your rotation allows", "Square hips", "Both heels down"],
   TURNOUT, ["glutes", "core"],
   [K("third", d=1.0), K("third", "third", d=1.0)], hero=1)
mv("fourth_position", "Quatrième position", "Fourth position", "positions", 1,
   "One foot in front of the other, a foot's length apart, both turned out — the classic pirouette preparation.",
   ["Weight centred between the feet", "Hips square to the front", "Back heel pressing down"],
   TURNOUT, ["glutes", "core", "calves"],
   [K("fourth", d=1.0), K("fourth", "third", d=1.0)], hero=1)
mv("fifth_position", "Cinquième position", "Fifth position", "positions", 1,
   "Feet fully crossed, heel of the front foot to the toe of the back. The home of classical ballet.",
   ["Wrap the thighs together", "Lift out of the hips", "Front heel forward, back heel back"],
   TURNOUT + ["glutes"], ["core", "hamstrings"],
   [K("fifth", d=1.0), K("fifth", "fifth", d=1.0)], hero=1)
mv("parallel", "Position parallèle", "Sixth / parallel position", "positions", 1,
   "Feet side by side, pointing forward. Common in warm-ups and contemporary-leaning classes.",
   ["Toes and knees face forward", "Weight even", "Soft knees, never locked"],
   ["core", "quadriceps"], ["calves"],
   [K("first", d=1.0), K("first", "demi_second", d=1.0)], hero=0)
mv("cou_de_pied", "Sur le cou-de-pied", "On the neck of the foot", "positions", 1,
   "The working foot wraps the supporting ankle, front or back — the starting point of frappés and petits battements.",
   ["Heel forward, toes back (wrapped)", "Keep the working knee open", "Supporting leg tall"],
   ["foot_intrinsics", "deep_rotators"], ["calves", "core"],
   [K("fifth", "barre", d=0.6), K("coupe_front", "barre", d=0.6), K("coupe_front", "barre", d=0.8), K("coupe_back", "barre", d=0.6), K("coupe_back", "barre", d=0.8)], hero=1)
mv("retire_position", "Retiré", "Withdrawn (passé position)", "positions", 1,
   "The working toe draws up the leg to touch just below the knee, thigh rotated out to the side.",
   ["Knee to the side, not forward", "Toe connects to the knee", "Hips level"],
   ["hip_flexors", "deep_rotators"], ["core", "glutes", "foot_intrinsics"],
   [K("fifth", "barre", d=0.6), K("retire", "barre", d=0.8), K("retire", "barre", d=0.8)], hero=1, aka=["Passé"])

# ───────────────────────────── Port de bras ─────────────────────────────
mv("bras_bas", "Bras bas", "Arms low (preparatory)", "port_de_bras", 1,
   "Arms rounded and low in front of the thighs, fingertips almost touching — the resting position.",
   ["Soft elbows, not touching the body", "Long neck", "Fingers relaxed and gathered"],
   ["deltoids", "arms"], ["trapezius"],
   [K("fifth", "bras_bas", d=1.0), K("fifth", "bras_bas", d=1.0)], hero=0)
mv("first_arms", "Première position des bras", "First position of the arms", "port_de_bras", 1,
   "Arms rounded in front of the body at the height of the lower ribs, as though holding a large ball.",
   ["Elbows lifted from behind", "Shoulders stay down", "Hands in line with the sternum"],
   ["deltoids", "arms"], ["lats", "trapezius"],
   [K("fifth", "bras_bas", d=0.9), K("fifth", "first", d=0.9), K("fifth", "first", d=0.8)], hero=1)
mv("second_arms", "Seconde position des bras", "Second position of the arms", "port_de_bras", 1,
   "Arms open to the sides, slightly in front of the shoulders and gently sloping down.",
   ["Support from the back muscles", "Elbows never drop", "Palms face forward-down"],
   ["deltoids", "lats"], ["trapezius", "arms"],
   [K("fifth", "first", d=0.9), K("fifth", "second", d=0.9), K("fifth", "second", d=0.8)], hero=1)
mv("third_arms", "Troisième position des bras", "Third position of the arms", "port_de_bras", 1,
   "One arm in first, the other open to second — a frame for épaulement.",
   ["Rounded front arm", "Open arm supported from the back", "Head can incline towards the front arm"],
   ["deltoids", "arms"], ["lats"],
   [K("fifth", "second", d=0.9), K("fifth", "third", d=0.9), K("fifth", "third", d=0.8)], hero=1)
mv("fourth_arms", "Quatrième position des bras", "Fourth position of the arms", "port_de_bras", 1,
   "One arm raised in fifth above the head while the other stays open in second.",
   ["Raised arm frames the face", "Shoulders level", "Ribs closed"],
   ["deltoids", "trapezius"], ["lats", "core"],
   [K("fifth", "second", d=0.9), K("fifth", "fourth", d=0.9), K("fifth", "fourth", d=0.8)], hero=1)
mv("fifth_arms", "Cinquième position des bras", "Fifth position of the arms (en haut)", "port_de_bras", 1,
   "Both arms raised in an oval just in front of and above the head.",
   ["See your hands without lifting the chin", "Shoulders down", "Long through the sides"],
   ["deltoids", "trapezius"], ["lats", "core"],
   [K("fifth", "first", d=0.9), K("fifth", "fifth", d=0.9), K("fifth", "fifth", d=0.8)], hero=1, aka=["En haut", "En couronne"])
mv("allonge", "Allongé", "Elongated arms", "port_de_bras", 2,
   "The arms lengthen and the palms turn down, extending the line to the fingertips — often finishing an arabesque.",
   ["Lengthen, don't lock, the elbows", "Breath into the gesture", "Line continues past the fingertips"],
   ["deltoids", "lats"], ["arms"],
   [K("fifth", "second", d=0.8), K("fifth", "allonge", d=0.8), K("fifth", "allonge", d=0.8)], hero=1)
mv("port_de_bras_forward", "Port de bras en avant", "Forward bend with the arms", "port_de_bras", 1,
   "The body folds forward from the hips, the arm following, then rolls up through the spine.",
   ["Hinge from the hips, long back first", "Head is the last to arrive", "Keep weight forward over the feet"],
   ["hamstrings", "erector_spinae"], ["core", "deltoids"],
   [K("first", "barre_fifth", d=0.8), K("first", "barre_fifth", "cambre_forward", d=1.2), K("first", "barre_fifth", d=1.2)], hero=1)
mv("cambre_back", "Cambré en arrière", "Arched backbend", "port_de_bras", 2,
   "The upper back arches backwards with the arm overhead, lifting up before going back.",
   ["Lift up, then back", "Keep the hips over the feet", "Neck is a continuation of the spine"],
   ["erector_spinae", "core"], ["obliques", "deltoids", "glutes"],
   [K("first", "barre_fifth", d=0.8), K("first", "barre_fifth", "cambre_back", d=1.2), K("first", "barre_fifth", d=1.2)], hero=1)
mv("cambre_side", "Cambré de côté", "Side bend", "port_de_bras", 1,
   "A lateral bend of the upper body, arm overhead, keeping both hips firmly down.",
   ["Lengthen before you bend", "Hips stay square and level", "Ribs open on the long side"],
   ["obliques", "lats"], ["core", "deltoids"],
   [K("first", "barre_fifth", d=0.8), K("first", "barre_fifth", "cambre_side", d=1.2), K("first", "barre_fifth", d=1.2)], hero=1)
mv("epaulement", "Épaulement", "Shouldering", "port_de_bras", 2,
   "A gentle spiral of the shoulders and head relative to the hips, giving three-dimensional life to every pose.",
   ["Rotate from the waist up", "Head inclines towards the front shoulder", "Keep the hips steady"],
   ["obliques", "core"], ["trapezius", "erector_spinae"],
   [K("fifth", "third", "epaulement_r", d=1.0), K("fifth", "third", "epaulement_l", d=1.0, m=True)], hero=0)
mv("reverence", "Révérence", "Curtsey / bow", "port_de_bras", 1,
   "The graceful thank-you at the end of class: step, extend the back leg and bow with open arms.",
   ["Arms open as if offering", "Back knee soft", "Gaze lowers with gratitude"],
   ["quadriceps", "glutes"], ["deltoids", "core"],
   [K("fifth", "bras_bas", d=0.8), K("second", "second", d=0.8), K("tendu_back_plie", "reverence", "bow", d=1.2), K("tendu_back_plie", "reverence", "bow", d=0.8)], hero=2)

# ───────────────────────────── Barre ─────────────────────────────
mv("demi_plie", "Demi-plié", "Half bend", "barre", 1,
   "A half bend of the knees with the heels firmly down, knees opening directly over the toes.",
   ["Heels stay glued to the floor", "Knees track over the toes", "Equal down and up, always lengthening"],
   ["quadriceps", "deep_rotators", "adductors"], ["calves", "glutes", "core"],
   [K("first", "barre", d=0.7), K("first_demi", "barre", d=1.0), K("first", "barre", d=1.0)])
mv("grand_plie", "Grand plié", "Full bend", "barre", 1,
   "A deep bend continuing past demi-plié; the heels release in first, fourth and fifth (never in second).",
   ["Pass through demi-plié on the way down and up", "Heels return to the floor as early as possible", "Spine stays vertical"],
   ["quadriceps", "adductors", "glutes"], ["deep_rotators", "calves", "core"],
   [K("first", "barre", d=0.8), K("first_demi", "barre_first", d=0.9), K("first_grand", "barre_bas", d=0.9), K("first_demi", "barre_first", d=0.9), K("first", "barre", d=0.9)], hero=2)
mv("grand_plie_second", "Grand plié en seconde", "Full bend in second", "barre", 1,
   "In second position the heels never leave the floor; the thighs stop just above knee height.",
   ["Heels stay down", "Knees push back over the toes", "Sit 'between' the legs, not behind them"],
   ["quadriceps", "adductors", "glutes"], ["deep_rotators", "core"],
   [K("second", "barre", d=0.8), K("second_demi", "barre", d=0.9), K("second_grand", "barre_bas", d=0.9), K("second_demi", "barre", d=0.9)], hero=2)
mv("battement_tendu", "Battement tendu", "Stretched beat", "barre", 1,
   "The working foot slides out along the floor until only the tips of the toes touch, then draws back to fifth.",
   ["Heel leads out, toes lead in", "Never lose contact with the floor", "Keep both hips square"],
   ["foot_intrinsics", "calves", "deep_rotators"], ["quadriceps", "adductors", "core"],
   [K("fifth", "barre", d=0.5), K("tendu_front", "barre", d=0.5), K("fifth", "barre", d=0.5), K("tendu_side", "barre", d=0.5), K("fifth", "barre", d=0.5, m=False), K("tendu_back", "barre", d=0.5), K("fifth", "barre", d=0.5), K("tendu_side", "barre", d=0.5)], hero=1, aka=["Tendu"])
mv("battement_tendu_plie", "Tendu with demi-plié", "Stretch and bend", "barre", 1,
   "The foot extends to tendu, lowers the heel into fourth or second in demi-plié, then stretches back.",
   ["Transfer the weight evenly", "Re-point the foot before closing", "No sinking in the hips"],
   ["quadriceps", "foot_intrinsics"], ["calves", "deep_rotators"],
   [K("fifth", "barre", d=0.6), K("tendu_side", "barre", d=0.6), K("second_demi", "barre", d=0.6), K("tendu_side", "barre", d=0.6), K("fifth", "barre", d=0.6)], hero=2)
mv("battement_degage", "Battement dégagé", "Disengaged beat", "barre", 1,
   "A quick tendu that brushes through and releases the foot about 25° off the floor.",
   ["Brush through the floor", "Accent out or in as the teacher asks", "Supporting side stays still"],
   ["foot_intrinsics", "quadriceps", "hip_flexors"], ["calves", "core", "deep_rotators"],
   [K("fifth", "barre", d=0.3), K("degage_front", "barre", d=0.3), K("fifth", "barre", d=0.3), K("degage_side", "barre", d=0.3), K("fifth", "barre", d=0.3), K("degage_back", "barre", d=0.3), K("fifth", "barre", d=0.3), K("degage_side", "barre", d=0.3)], hero=3, aka=["Battement jeté", "Glissé"])
mv("battement_piqué", "Battement piqué", "Pricked beat", "barre", 2,
   "From dégagé the pointed toe taps the floor lightly and rebounds, like a needle.",
   ["Rebound, don't drop", "Toe touches and lifts in the same breath", "Leg stays turned out"],
   ["foot_intrinsics", "hip_flexors"], ["quadriceps", "core"],
   [K("degage_side", "barre", d=0.3), K("tendu_side", "barre", d=0.2), K("degage_side", "barre", d=0.2), K("tendu_side", "barre", d=0.2)], hero=0)
mv("rond_de_jambe_a_terre", "Rond de jambe à terre", "Circle of the leg on the ground", "barre", 1,
   "The pointed foot traces a half-circle on the floor: front, side, back, and closes through first.",
   ["Rotation increases as the leg travels back", "Hips stay level", "Trace a perfect 'D' on the floor"],
   ["deep_rotators", "glutes"], ["adductors", "foot_intrinsics", "core"],
   [K("first", "barre", d=0.5), K("tendu_front", "barre", d=0.5), K("tendu_side", "barre", d=0.5), K("tendu_back", "barre", d=0.5), K("first", "barre", d=0.5)], hero=2, aka=["En dehors", "En dedans"])
mv("battement_fondu", "Battement fondu", "Melting beat", "barre", 2,
   "Both knees bend together as the working foot sits sur le cou-de-pied, then both legs stretch together as it unfolds.",
   ["Both legs bend and straighten at the same speed", "Smooth like melting butter", "Keep the knee of the working leg open"],
   ["quadriceps", "hip_flexors", "deep_rotators"], ["calves", "glutes", "core"],
   [K("fifth", "barre", d=0.6), K("fondu_coupe", "barre", d=0.8), K("fondu_side", "barre", d=0.9), K("fondu_coupe", "barre", d=0.9), K("fondu_front", "barre", d=0.9)], hero=2)
mv("battement_frappe", "Battement frappé", "Struck beat", "barre", 2,
   "From a flexed cou-de-pied the foot strikes out, brushing the floor, to a sharply pointed low extension.",
   ["Accent out, quick and clean", "Only the lower leg moves", "Thigh stays still and rotated"],
   ["foot_intrinsics", "calves", "quadriceps"], ["tibialis", "hamstrings"],
   [K("coupe_flex", "barre", d=0.4), K("frappe_side", "barre", d=0.2), K("coupe_flex", "barre", d=0.4), K("frappe_front", "barre", d=0.2)], hero=1)
mv("double_frappe", "Double frappé", "Double struck beat", "barre", 3,
   "Before striking, the foot beats front and back of the supporting ankle.",
   ["Beat from the knee down", "Thigh absolutely still", "Crisp, even rhythm"],
   ["foot_intrinsics", "calves", "hamstrings"], ["tibialis", "quadriceps"],
   [K("coupe_flex", "barre", d=0.3), K("coupe_back", "barre", d=0.15), K("coupe_flex", "barre", d=0.15), K("frappe_side", "barre", d=0.2)], hero=3)
mv("petit_battement", "Petit battement sur le cou-de-pied", "Small beats at the ankle", "barre", 3,
   "Rapid small beats of the working foot alternating in front and behind the supporting ankle.",
   ["Move only from the knee down", "Keep the thigh rotated", "Light and fast"],
   ["hamstrings", "deep_rotators"], ["foot_intrinsics", "calves"],
   [K("coupe_front", "barre", d=0.18), K("coupe_back", "barre", d=0.18)], hero=0)
mv("rond_de_jambe_en_lair", "Rond de jambe en l'air", "Circle of the leg in the air", "barre", 3,
   "With the thigh held à la seconde, the lower leg traces small ovals from the knee.",
   ["Thigh does not move", "Oval goes in to the calf and out to the extension", "Supporting hip lifted"],
   ["hamstrings", "hip_flexors", "deep_rotators"], ["quadriceps", "glutes", "core"],
   [K("rja_side", "barre", d=0.4), K("rja_in", "barre", d=0.3), K("rja_side", "barre", d=0.3)], hero=0)
mv("developpe", "Développé", "Developed / unfolded", "barre", 2,
   "The working foot draws up through retiré and unfolds the leg slowly to its full height.",
   ["Pass through retiré", "Hold the thigh, unfold the lower leg", "Lengthen the leg away as it rises"],
   ["hip_flexors", "quadriceps", "glutes"], ["core", "deep_rotators", "hamstrings"],
   [K("fifth", "barre", d=0.8), K("retire", "barre_first", d=0.9), K("developpe_side", "barre", d=1.0), K("developpe_side", "barre", d=0.6), K("fifth", "barre", d=0.9)], hero=2)
mv("enveloppe", "Enveloppé", "Enveloped", "barre", 2,
   "The reverse of développé: the extended leg folds in to retiré and closes.",
   ["Thigh holds as the lower leg folds", "Arrive at the knee before closing", "Supporting leg stays pulled up"],
   ["hip_flexors", "hamstrings"], ["quadriceps", "core"],
   [K("developpe_side", "barre", d=0.8), K("retire", "barre", d=0.9), K("fifth", "barre", d=0.9)], hero=0)
mv("grand_battement", "Grand battement", "Big beat", "barre", 2,
   "The straight leg is thrown high through tendu and lowered with control.",
   ["Brush through the floor", "Up with energy, down with control", "Torso stays still"],
   ["hip_flexors", "quadriceps", "hamstrings"], ["glutes", "core", "foot_intrinsics"],
   [K("fifth", "barre", d=0.5), K("battement_front", "barre", d=0.35), K("fifth", "barre", d=0.5), K("battement_side", "barre", d=0.35), K("fifth", "barre", d=0.5), K("battement_back", "barre", "arabesque_lean", d=0.35), K("fifth", "barre", d=0.5)], hero=1)
mv("battement_en_cloche", "Battement en cloche", "Bell beat", "barre", 2,
   "A grand battement that swings like a bell from front to back through first position.",
   ["Swing passes through first", "Hips stay square front", "Controlled at both ends"],
   ["hip_flexors", "hamstrings", "glutes"], ["core", "quadriceps"],
   [K("battement_front", "barre", d=0.5), K("first", "barre", d=0.35), K("battement_back", "barre", "arabesque_lean", d=0.35), K("first", "barre", d=0.35)], hero=0)
mv("releve", "Relevé", "Raised", "barre", 1,
   "Rising onto demi-pointe (or pointe), often springing in from a demi-plié.",
   ["Push the floor away", "Ankles stay straight, no sickling", "Pull up through the core"],
   ["calves", "foot_intrinsics"], ["core", "glutes", "quadriceps"],
   [K("first", "barre", d=0.6), K("first_demi", "barre", d=0.5), K("first_releve", "barre", d=0.4), K("first_releve", "barre", d=0.5)], hero=2)
mv("eleve", "Élevé", "Rise without plié", "barre", 1,
   "Rising to demi-pointe with straight knees — pure foot and calf strength.",
   ["Rise through all of the foot", "Lower slowly through the heel", "Weight over the second toe"],
   ["calves", "foot_intrinsics"], ["core", "tibialis"],
   [K("first", "barre", d=0.7), K("first_releve", "barre", d=0.8), K("first_releve", "barre", d=0.5)], hero=1)
mv("sous_sus", "Sous-sus", "Under-over", "barre", 1,
   "A relevé into a tight fifth position, the legs so crossed they look like one.",
   ["Pull the feet under the centre", "Thighs glued together", "Tall and still at the top"],
   ["calves", "adductors", "deep_rotators"], ["core", "glutes"],
   [K("fifth", "barre", d=0.6), K("fifth_demi", "barre", d=0.5), K("sous_sus", "barre_fifth", d=0.4), K("sous_sus", "barre_fifth", d=0.6)], hero=2, aka=["Sus-sous"])
mv("battement_soutenu", "Battement soutenu", "Sustained beat", "barre", 2,
   "The supporting leg bends while the working leg extends; both draw together into relevé in fifth.",
   ["Pull the legs together like a zip", "Arrive in a tight sous-sus", "Smooth, continuous"],
   ["adductors", "calves", "quadriceps"], ["core", "deep_rotators"],
   [K("fifth", "barre", d=0.6), K("tendu_side_plie", "barre", d=0.7), K("sous_sus", "barre", d=0.6)], hero=1)
mv("flic_flac", "Flic-flac", "Whip-crack", "barre", 3,
   "The working foot brushes in and out past the supporting ankle, closing and opening like a whip.",
   ["Ball of the foot brushes the floor", "Quick in, quicker out", "Knee stays open"],
   ["foot_intrinsics", "hamstrings"], ["calves", "deep_rotators"],
   [K("degage_side", "barre", d=0.3), K("coupe_front", "barre", d=0.15), K("coupe_back", "barre", d=0.15), K("degage_side", "barre", d=0.2)], hero=0)
mv("battement_battu", "Battement battu", "Beaten beat", "barre", 3,
   "Fast beats of the working foot against the front or back of the supporting ankle, on demi-pointe.",
   ["Very small and very quick", "Thigh stays still", "Stay up on the supporting foot"],
   ["hamstrings", "calves"], ["foot_intrinsics", "core"],
   [K("coupe_releve", "barre", d=0.15), K("coupe_front", "barre", d=0.15)], hero=0)
mv("passe_releve", "Passé relevé", "Passé on demi-pointe", "barre", 1,
   "From fifth, the working foot travels up to retiré as the supporting leg rises to relevé.",
   ["Arrive at the knee and the relevé together", "Close with control to fifth back", "Balance over the ball of the foot"],
   ["calves", "hip_flexors", "core"], ["deep_rotators", "glutes"],
   [K("fifth_demi", "barre", d=0.5), K("retire_releve", "barre_first", d=0.4), K("retire_releve", "barre_first", d=0.6), K("fifth", "barre", d=0.5)], hero=1)
mv("stretch_barre", "Stretch at the barre", "Leg on the barre", "barre", 1,
   "The leg rests on the barre while the body folds over it and then side bends, lengthening the hamstrings.",
   ["Square hips", "Long spine before folding", "Breathe into the stretch, never bounce"],
   ["hamstrings", "adductors"], ["erector_spinae", "calves"],
   [K("developpe_front", "barre", d=1.0), K("developpe_front", "barre_fifth", "cambre_forward", d=1.4), K("developpe_front", "barre", d=1.2)], hero=1)

# ───────────────────────────── Centre & adagio ─────────────────────────────
mv("arabesque_first", "Première arabesque", "First arabesque", "center", 2,
   "Standing on one leg, the other extended straight behind; the arm on the supporting side reaches forward.",
   ["Rotate and lengthen the back leg", "Lift the chest, let the back curve naturally", "Front arm in line with the eye"],
   ["glutes", "hamstrings", "erector_spinae"], ["core", "deltoids", "calves"],
   [K("fifth", "bras_bas", d=0.8), K("tendu_back", "first", d=0.6), K("arabesque", "arabesque1", "arabesque_lean", d=0.8), K("arabesque", "arabesque1", "arabesque_lean", d=1.0)], hero=2)
mv("arabesque_second", "Deuxième arabesque", "Second arabesque", "center", 2,
   "As first arabesque, but the opposite arm reaches forward, giving a spiral through the shoulders.",
   ["Spiral from the waist", "Keep the back leg rotated", "Gaze over the front arm"],
   ["glutes", "hamstrings", "erector_spinae"], ["obliques", "core", "deltoids"],
   [K("fifth", "bras_bas", d=0.8), K("arabesque", "arabesque2", "arabesque_lean", d=0.9), K("arabesque", "arabesque2", "arabesque_lean", d=1.0)], hero=1)
mv("arabesque_penchee", "Arabesque penchée", "Leaning arabesque", "center", 3,
   "From arabesque the body tips forward as the leg rises, like a see-saw, keeping the line from fingertips to toes.",
   ["Leg rises as the body lowers", "Keep the hips open but level", "Supporting leg firmly pulled up"],
   ["hamstrings", "glutes", "erector_spinae"], ["core", "calves", "adductors"],
   [K("arabesque", "arabesque1", "arabesque_lean", d=0.9), K("penche_leg", "arabesque1", "penche", d=1.3), K("arabesque", "arabesque1", "arabesque_lean", d=1.3)], hero=1, aka=["Penché"])
mv("arabesque_releve", "Arabesque relevée", "Arabesque on demi-pointe", "center", 3,
   "Arabesque taken up onto demi-pointe or pointe, usually from a demi-plié.",
   ["Push up from the plié", "Don't let the leg drop as you rise", "Lift out of the supporting hip"],
   ["calves", "glutes", "hamstrings"], ["core", "erector_spinae"],
   [K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.8), K("arabesque_releve", "arabesque1", "arabesque_lean", d=0.5), K("arabesque_releve", "arabesque1", "arabesque_lean", d=0.8)], hero=1)
mv("attitude_derriere", "Attitude derrière", "Attitude behind", "center", 2,
   "The leg lifts behind with the knee bent at about 90°, knee higher than the foot, arm raised in fifth.",
   ["Knee higher than the foot", "Rotate the thigh outward", "Lift the chest, don't collapse forward"],
   ["glutes", "hamstrings", "deep_rotators"], ["erector_spinae", "core", "calves"],
   [K("fifth", d=0.8), K("attitude_back", "fourth", d=0.9), K("attitude_back", "fourth", d=1.0)], hero=1)
mv("attitude_devant", "Attitude devant", "Attitude in front", "center", 2,
   "The leg lifts in front with a soft, rounded knee, heel pressing forward.",
   ["Heel leads forward", "Knee and foot at similar heights", "Sit up, don't lean back"],
   ["hip_flexors", "quadriceps", "deep_rotators"], ["core", "calves"],
   [K("fifth", d=0.8), K("attitude_front", "fourth", d=0.9), K("attitude_front", "fourth", d=1.0)], hero=1)
mv("developpe_devant", "Développé devant", "Unfolding to the front", "center", 2,
   "Through retiré, the leg unfolds forward to 90° or higher.",
   ["Pull the heel forward as you unfold", "Supporting side lifted", "Don't hitch the hip"],
   ["hip_flexors", "quadriceps"], ["core", "deep_rotators", "calves"],
   [K("fifth", d=0.8), K("retire", "first", d=0.8), K("developpe_front", "second", d=1.0), K("developpe_front", "second", d=0.8), K("fifth", d=0.9)], hero=2)
mv("developpe_seconde", "Développé à la seconde", "Unfolding to the side", "center", 3,
   "The leg unfolds to the side at hip height or higher while the torso stays perfectly vertical.",
   ["Lift the leg from underneath", "Heel forward", "Don't let the working hip rise"],
   ["hip_flexors", "glutes", "deep_rotators"], ["quadriceps", "core", "obliques"],
   [K("fifth", d=0.8), K("retire", "first", d=0.8), K("developpe_side", "second", d=1.0), K("developpe_side", "second", d=0.8), K("fifth", d=0.9)], hero=2)
mv("developpe_derriere", "Développé derrière", "Unfolding to the back", "center", 3,
   "Through retiré the leg extends behind into arabesque or attitude line.",
   ["Lift the leg as the chest lifts", "Rotate the back thigh", "Keep the shoulders level"],
   ["glutes", "hamstrings", "erector_spinae"], ["core", "deltoids"],
   [K("fifth", d=0.8), K("retire", "first", d=0.8), K("developpe_back", "arabesque1", "arabesque_lean", d=1.0), K("developpe_back", "arabesque1", "arabesque_lean", d=0.8), K("fifth", d=0.9)], hero=2)
mv("grand_rond_de_jambe", "Grand rond de jambe en l'air", "Large circle of the leg", "center", 3,
   "The leg sweeps at 90° from front to side to back (or reverse) in one continuous arc.",
   ["Rotation increases as the leg passes to the back", "Torso responds only slightly", "Continuous speed through the arc"],
   ["hip_flexors", "glutes", "deep_rotators"], ["core", "obliques", "hamstrings"],
   [K("developpe_front", "second", d=0.8), K("developpe_side", "second", d=0.8), K("developpe_back", "arabesque1", "arabesque_lean", d=0.8), K("fifth", d=0.8)], hero=1)
mv("temps_lie", "Temps lié", "Linked movement", "center", 1,
   "A flowing transfer of weight through demi-plié and tendu that links positions, travelling forward and sideways.",
   ["Pass through a clean fourth", "Weight transfers smoothly", "Arms breathe with the legs"],
   ["quadriceps", "deep_rotators"], ["glutes", "core", "foot_intrinsics"],
   [K("fifth_demi", "first", d=0.6), K("tendu_front_plie", "first", d=0.6), K("tendu_back", "fourth", d=0.7, dz=0.15), K("fifth", "bras_bas", d=0.6, dz=0.15), K("tendu_side_plie", "first", d=0.6, dz=0.15), K("tendu_side", "second", d=0.6, dx=-0.15, dz=0.15), K("fifth", d=0.7)], hero=2)
mv("promenade", "Promenade", "Slow turn on a flat foot", "center", 3,
   "Holding a pose such as attitude or arabesque, the dancer pivots slowly in a full circle by small heel shifts.",
   ["Keep the pose absolutely still", "Small heel adjustments", "Spot slowly, or keep the head with the body"],
   ["glutes", "calves", "core"], ["hamstrings", "deep_rotators", "erector_spinae"],
   [K("attitude_back", "fourth", d=0.8, yaw=0), K("attitude_back", "fourth", d=2.4, yaw=180), K("attitude_back", "fourth", d=2.4, yaw=360)], hero=0, aka=["Tour lent"])
mv("croise_devant", "Croisé devant", "Crossed in front", "center", 2,
   "A body direction: angled to the corner with the downstage leg extended to the front — legs appear crossed.",
   ["Hips and shoulders to the corner", "Head towards the audience", "Downstage arm low"],
   ["hip_flexors", "obliques"], ["core", "deep_rotators"],
   [K("fifth", d=0.7, yaw=0), K("tendu_front", "fourth", "epaulement_r", d=0.8, yaw=-35), K("tendu_front", "fourth", "epaulement_r", d=0.8, yaw=-35)], hero=1)
mv("effacé_devant", "Effacé devant", "Shaded / open in front", "center", 2,
   "A body direction angled to the corner with the upstage leg in front, giving an open, 'shaded' line.",
   ["Open the chest", "Lean very slightly back", "Head looks over the raised arm"],
   ["hip_flexors", "obliques"], ["core", "deep_rotators"],
   [K("fifth", d=0.7, yaw=0), K("tendu_front", "fourth", "epaulement_l", d=0.8, yaw=35), K("tendu_front", "fourth", "epaulement_l", d=0.8, yaw=35)], hero=1, aka=["Effacé"])
mv("ecarte", "Écarté", "Separated / thrown wide", "center", 3,
   "Facing the corner, the leg extends to the side towards the other corner, the body inclining away.",
   ["Body tilts away from the leg", "Look up to the raised hand or down", "Strong supporting side"],
   ["obliques", "hip_flexors", "glutes"], ["core", "deep_rotators"],
   [K("fifth", d=0.7, yaw=0), K("developpe_side", "fourth", "cambre_side", d=1.0, yaw=-40), K("developpe_side", "fourth", "cambre_side", d=0.8, yaw=-40)], hero=1)
mv("a_la_quatrieme", "À la quatrième devant", "Fourth front", "center", 2,
   "Facing the audience squarely, the leg extends straight in front.",
   ["Square hips", "Heel forward", "Arms in second"],
   ["hip_flexors", "quadriceps"], ["core"],
   [K("fifth", d=0.7), K("developpe_front", "second", d=0.9), K("developpe_front", "second", d=0.8)], hero=1)
mv("renverse", "Renversé", "Upset / overturned", "center", 4,
   "A turning movement in which the upper body bends back deeply from attitude, finishing in a pas de bourrée.",
   ["Bend from the upper back only", "Keep the attitude knee lifted", "Let the head finish the turn"],
   ["erector_spinae", "obliques", "glutes"], ["calves", "core", "hamstrings"],
   [K("attitude_back_releve", "fifth", d=0.8, yaw=0), K("attitude_back_releve", "fifth", "cambre_back", d=0.8, yaw=180), K("fifth", "first", d=0.7, yaw=360)], hero=1)
mv("balance_releve", "Balance in retiré", "Retiré balance", "center", 2,
   "A sustained balance on demi-pointe in retiré with arms in fifth.",
   ["Stack hips over the ball of the foot", "Breathe and lengthen", "Active, not frozen"],
   ["calves", "core", "deep_rotators"], ["glutes", "foot_intrinsics"],
   [K("fifth_demi", "first", d=0.7), K("retire_releve", "fifth", d=0.5), K("retire_releve", "fifth", d=1.6)], hero=1)

# ───────────────────────────── Turns ─────────────────────────────
mv("pirouette_en_dehors", "Pirouette en dehors", "Outward turn", "turns", 2,
   "From fourth position the dancer rises to retiré and turns away from the supporting leg.",
   ["Push equally from both feet", "Arrive in retiré and relevé together", "Spot: head last to leave, first to arrive"],
   ["calves", "core", "deep_rotators"], ["obliques", "glutes", "hip_flexors"],
   [K("fourth_demi", "third", d=0.7, yaw=0), K("retire_releve", "first", d=0.25, yaw=90), K("retire_releve", "first", d=0.45, yaw=360), K("fifth_demi", "second", d=0.4, yaw=360)], hero=2)
mv("double_pirouette", "Double pirouette en dehors", "Double outward turn", "turns", 3,
   "Two rotations in retiré from a fourth-position preparation.",
   ["More height, not more force", "Spot twice, quickly", "Hold the retiré firmly"],
   ["calves", "core", "deep_rotators"], ["obliques", "glutes"],
   [K("fourth_demi", "third", d=0.7, yaw=0), K("retire_releve", "first", d=0.25, yaw=120), K("retire_releve", "first", d=0.7, yaw=720), K("fifth_demi", "second", d=0.4, yaw=720)], hero=2)
mv("pirouette_en_dedans", "Pirouette en dedans", "Inward turn", "turns", 3,
   "A turn towards the supporting leg; the working leg opens and then draws into retiré.",
   ["Use the working leg to start the turn", "Stay on top of the supporting leg", "Arms close quickly to first"],
   ["calves", "core", "obliques"], ["deep_rotators", "hip_flexors"],
   [K("fourth_lunge", "third", d=0.7, yaw=0), K("retire_releve", "first", d=0.25, yaw=-90), K("retire_releve", "first", d=0.45, yaw=-360), K("fifth_demi", "second", d=0.4, yaw=-360)], hero=2)
mv("pique_turn", "Piqué tour en dedans", "Stepping turn inward", "turns", 2,
   "The dancer steps directly onto a straight leg on demi-pointe and turns in retiré, travelling on a line.",
   ["Step out on a straight leg", "Pull the retiré up quickly", "Spot down the line"],
   ["calves", "core", "quadriceps"], ["deep_rotators", "obliques"],
   [K("tendu_side_plie", "second", d=0.5, yaw=0, dx=0), K("retire_releve", "first", d=0.25, yaw=-120, dx=-0.25), K("retire_releve", "first", d=0.4, yaw=-360, dx=-0.3), K("tendu_side_plie", "second", d=0.4, yaw=-360, dx=-0.3)], hero=2)
mv("chaine", "Chaînés", "Chained turns", "turns", 2,
   "A series of quick half-turns on demi-pointe, feet close together in first, travelling in a line or circle.",
   ["Feet stay close", "Arms close in to first", "Spot quickly, keep the knees pulled up"],
   ["calves", "core", "adductors"], ["obliques", "foot_intrinsics"],
   [K("first_releve", "first", d=0.25, yaw=0, dx=0), K("first_releve", "first", d=0.25, yaw=-180, dx=-0.15), K("first_releve", "first", d=0.25, yaw=-360, dx=-0.3), K("first_releve", "first", d=0.25, yaw=-540, dx=-0.45), K("first_releve", "first", d=0.25, yaw=-720, dx=-0.6)], hero=1, aka=["Déboulés"])
mv("soutenu_turn", "Soutenu en tournant", "Sustained turn", "turns", 1,
   "Drawing the working leg into sous-sus, the dancer turns a full revolution on both feet.",
   ["Pull the legs tightly together", "Change feet as you complete the turn", "Lift up, don't hop"],
   ["calves", "adductors", "core"], ["deep_rotators", "obliques"],
   [K("tendu_side_plie", "second", d=0.6, yaw=0), K("sous_sus", "fifth", d=0.35, yaw=-180), K("sous_sus", "fifth", d=0.4, yaw=-360), K("fifth", "bras_bas", d=0.5, yaw=-360)], hero=2)
mv("fouette_turns", "Fouetté rond de jambe en tournant", "Whipped turns", "turns", 4,
   "The famous series of turns: the working leg whips out to the side and in to retiré, sustaining continuous rotation.",
   ["Open the leg front before whipping it to the side", "Plié on every return", "Hips stay square during the whip"],
   ["calves", "hip_flexors", "core"], ["glutes", "obliques", "quadriceps", "deep_rotators"],
   [K("seconde_plie", "second", d=0.35, yaw=0), K("retire_releve", "first", d=0.25, yaw=-180), K("retire_releve", "first", d=0.2, yaw=-360), K("seconde_plie", "second", d=0.2, yaw=-360)], hero=0, aka=["Fouettés"])
mv("tour_a_la_seconde", "Grande pirouette à la seconde", "Turning with the leg in second", "turns", 4,
   "Multiple turns holding the leg at 90° to the side, often with hops of the supporting heel — a male virtuoso step.",
   ["Leg stays high and still", "Push from small plié-relevés", "Spot every rotation"],
   ["hip_flexors", "calves", "core"], ["glutes", "quadriceps", "deep_rotators"],
   [K("seconde_releve", "second", d=0.5, yaw=0), K("seconde_releve", "second", d=0.5, yaw=-180), K("seconde_releve", "second", d=0.5, yaw=-360)], hero=0)
mv("attitude_turn", "Pirouette en attitude", "Turn in attitude", "turns", 4,
   "A pirouette with the working leg held in attitude derrière and the arm raised in fifth.",
   ["Lift the knee higher than the foot", "Lean slightly into the turn", "Keep the chest lifted"],
   ["glutes", "calves", "core"], ["hamstrings", "erector_spinae"],
   [K("fourth_demi", "third", d=0.6, yaw=0), K("attitude_back_releve", "fourth", d=0.3, yaw=-120), K("attitude_back_releve", "fourth", d=0.5, yaw=-360), K("fifth_demi", "second", d=0.4, yaw=-360)], hero=2)
mv("arabesque_turn", "Pirouette en arabesque", "Turn in arabesque", "turns", 4,
   "Turning on demi-pointe with the leg extended behind in arabesque.",
   ["Commit to the line before the turn", "Don't let the leg drop", "Spot over the front arm"],
   ["glutes", "calves", "erector_spinae"], ["hamstrings", "core"],
   [K("fourth_demi", "third", d=0.6, yaw=0), K("arabesque_releve", "arabesque1", "arabesque_lean", d=0.3, yaw=-120), K("arabesque_releve", "arabesque1", "arabesque_lean", d=0.5, yaw=-360), K("fifth_demi", "second", d=0.4, yaw=-360)], hero=2)
mv("pique_en_dehors", "Piqué en dehors", "Lame duck", "turns", 3,
   "A piqué onto a straight leg turning outward, the working foot flicking to retiré behind.",
   ["Step and turn away from the supporting leg", "Quick coupé behind", "Spot to the line"],
   ["calves", "core"], ["hamstrings", "obliques"],
   [K("tendu_side_plie", "second", d=0.5, yaw=0), K("retire_releve", "first", d=0.25, yaw=150, dx=0.25), K("retire_releve", "first", d=0.35, yaw=360, dx=0.3), K("tendu_side_plie", "second", d=0.4, yaw=360, dx=0.3, m=True)], hero=2, aka=["Lame duck"])
mv("tour_en_lair", "Tour en l'air", "Turn in the air", "turns", 4,
   "From fifth position, a vertical jump with one or two full rotations, landing in fifth — a classical male step.",
   ["Arms close to fifth or first instantly", "Change the feet in the air", "Land through demi-plié"],
   ["quadriceps", "calves", "core"], ["glutes", "adductors", "obliques"],
   [K("fifth_demi", "second", d=0.6, yaw=0), K("air_tour", "first", d=0.3, yaw=-360), K("air_tour", "first", d=0.25, yaw=-720), K("fifth_demi", "second", d=0.3, yaw=-720, m=True)], hero=1)
mv("coupe_jete_en_tournant", "Coupé jeté en tournant", "Cut and thrown, turning", "turns", 4,
   "A travelling turning jump in a circle: a coupé step, a half turn and a throw of the leg into a split jeté.",
   ["Throw the front leg high", "Turn on the step, not in the air", "Travel around the circle"],
   ["quadriceps", "hip_flexors", "glutes"], ["calves", "hamstrings", "core"],
   [K("fondu_coupe", "first", d=0.4, yaw=0), K("air_split", "fourth", "arabesque_lean", d=0.35, yaw=-180, dx=-0.3), K("fondu_coupe", "first", d=0.35, yaw=-360, dx=-0.5)], hero=1)

# ───────────────────────────── Petit allegro ─────────────────────────────
mv("saute", "Sauté", "Jump", "petit_allegro", 1,
   "A simple jump from two feet, keeping the position (first, second or fifth) in the air.",
   ["Push through the floor with the toes", "Point the feet instantly", "Land toe-ball-heel into plié"],
   ["calves", "quadriceps", "glutes"], ["foot_intrinsics", "core"],
   [K("first_demi", "bras_bas", d=0.45), K("air_first", "bras_bas", d=0.25), K("first_demi", "bras_bas", d=0.25)], hero=1, aka=["Temps levé"])
mv("changement", "Changement de pieds", "Change of feet", "petit_allegro", 1,
   "A jump from fifth in which the feet change in the air, landing with the other foot in front.",
   ["Show both legs straight in the air", "Change only at the top", "Close into a clean fifth"],
   ["calves", "adductors", "quadriceps"], ["foot_intrinsics", "glutes", "core"],
   [K("fifth_demi", d=0.45), K("air_fifth", d=0.25), K("fifth_demi", d=0.25, m=True), K("air_fifth", d=0.25, m=True), K("fifth_demi", d=0.25)], hero=1)
mv("echappe_saute", "Échappé sauté", "Escaping jump", "petit_allegro", 1,
   "From fifth the legs 'escape' to second (or fourth) in the air and land apart, then close back.",
   ["Open in the air, not on the floor", "Land with knees over toes", "Close to fifth with the other foot front"],
   ["calves", "quadriceps", "adductors"], ["glutes", "core"],
   [K("fifth_demi", d=0.4), K("air_second", "demi_second", d=0.25), K("second_demi", "second", d=0.25), K("air_second", "demi_second", d=0.25), K("fifth_demi", d=0.25, m=True)], hero=1)
mv("assemble", "Assemblé", "Assembled", "petit_allegro", 2,
   "The working leg brushes out, the dancer springs, and both legs join together in the air before landing in fifth.",
   ["Brush through the floor", "Join the legs at the top of the jump", "Land in fifth at the same time on both feet"],
   ["quadriceps", "calves", "adductors"], ["hip_flexors", "glutes", "core"],
   [K("fifth_demi", "first", d=0.45), K("degage_side", "second", d=0.15), K("air_fifth", "second", d=0.2), K("fifth_demi", "first", d=0.25, m=True)], hero=2)
mv("petit_jete", "Petit jeté", "Small thrown jump", "petit_allegro", 2,
   "A brushing jump from one foot to the other, landing with the working foot wrapped behind the ankle.",
   ["Brush and throw the leg", "Land on the opposite foot in fondu", "Arrive sur le cou-de-pied"],
   ["calves", "quadriceps", "foot_intrinsics"], ["glutes", "hamstrings"],
   [K("fifth_demi", d=0.4), K("air_jete", "third", d=0.25, dx=-0.05), K("fondu_coupe", "third", d=0.25, dx=-0.1, m=True)], hero=1, aka=["Jeté"])
mv("glissade", "Glissade", "Glide", "petit_allegro", 1,
   "A gliding travelling step: the foot slides out, the body passes over, and the other foot closes in fifth.",
   ["Stay low and smooth", "Both feet point in the air briefly", "Close firmly in fifth"],
   ["quadriceps", "adductors"], ["calves", "foot_intrinsics", "core"],
   [K("fifth_demi", "demi_second", d=0.4), K("tendu_side_plie", "demi_second", d=0.25), K("second_releve", "demi_second", d=0.2, dx=-0.15), K("fifth_demi", "demi_second", d=0.25, dx=-0.3)], hero=2)
mv("pas_de_chat", "Pas de chat", "Step of the cat", "petit_allegro", 2,
   "A sideways jump where each leg lifts in succession to retiré, like a cat leaping, landing in fifth.",
   ["First leg up, second follows quickly", "Show both knees open", "Travel slightly to the side"],
   ["hip_flexors", "calves", "quadriceps"], ["deep_rotators", "glutes", "core"],
   [K("fifth_demi", "third", d=0.45), K("retire", "third", d=0.15, dx=-0.05), K("air_pas_de_chat", "third", d=0.2, dx=-0.15), K("fifth_demi", "third", d=0.25, dx=-0.25)], hero=2)
mv("sissonne_simple", "Sissonne simple", "Scissor-jump (simple)", "petit_allegro", 2,
   "A jump from two feet landing on one, with the other foot arriving sur le cou-de-pied.",
   ["Spring from both feet", "Land on one foot in plié", "Working foot wraps immediately"],
   ["calves", "quadriceps"], ["foot_intrinsics", "glutes"],
   [K("fifth_demi", d=0.45), K("air_fifth", d=0.2), K("fondu_coupe", "first", d=0.25)], hero=2)
mv("sissonne_fermee", "Sissonne fermée", "Closed scissor-jump", "petit_allegro", 2,
   "A jump from two feet that opens the legs in the air and closes quickly into fifth, travelling.",
   ["The back leg closes immediately", "Travel in the direction of the front foot", "Land both feet together"],
   ["quadriceps", "glutes", "adductors"], ["calves", "hamstrings", "core"],
   [K("fifth_demi", "first", d=0.45), K("air_sissonne", "arabesque2", "arabesque_lean", d=0.25, dz=0.15), K("fifth_demi", "first", d=0.25, dz=0.25)], hero=1)
mv("sissonne_ouverte", "Sissonne ouverte", "Open scissor-jump", "petit_allegro", 3,
   "Spring from two feet and land on one, holding the other leg open in the air — arabesque, attitude or à la seconde.",
   ["Show the open leg at the top", "Land with the leg still up", "Strong back"],
   ["glutes", "quadriceps", "hamstrings"], ["calves", "core", "erector_spinae"],
   [K("fifth_demi", "first", d=0.45), K("air_sissonne", "arabesque1", "arabesque_lean", d=0.25, dz=0.15), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.3, dz=0.25)], hero=2)
mv("entrechat_quatre", "Entrechat quatre", "Interwoven jump — four", "petit_allegro", 3,
   "A vertical jump in which the legs open and close, beating twice before landing in fifth with the same foot in front.",
   ["Beat with the thighs, not the feet", "Legs open only slightly", "Straight knees, stretched feet"],
   ["adductors", "calves", "quadriceps"], ["foot_intrinsics", "core"],
   [K("fifth_demi", d=0.4), K("air_second", d=0.12), K("air_fifth", d=0.1, m=True), K("air_fifth", d=0.08), K("fifth_demi", d=0.25)], hero=2)
mv("entrechat_six", "Entrechat six", "Interwoven jump — six", "petit_allegro", 4,
   "Three crossings of the legs in the air, landing with the opposite foot in front.",
   ["Jump higher, beat faster", "Hold the body completely still", "Arms help lift"],
   ["adductors", "calves", "quadriceps"], ["glutes", "core"],
   [K("fifth_demi", "first", d=0.4), K("air_second", "first", d=0.1), K("air_fifth", "first", d=0.08, m=True), K("air_second", "first", d=0.08), K("air_fifth", "first", d=0.08), K("fifth_demi", "first", d=0.25, m=True)], hero=2)
mv("royale", "Royale", "Royal (changement battu)", "petit_allegro", 3,
   "A changement with a beat: the legs beat once in front before changing.",
   ["Beat front, then change", "Keep the hips square", "Light, quick feet"],
   ["adductors", "calves"], ["quadriceps", "core"],
   [K("fifth_demi", d=0.4), K("air_fifth", d=0.15), K("air_second", d=0.1), K("fifth_demi", d=0.25, m=True)], hero=1)
mv("brise", "Brisé", "Broken", "petit_allegro", 4,
   "A small travelling beaten assemblé: the working leg brushes, beats against the other in the air, and lands in fifth.",
   ["Travel towards the brushing leg", "Beat at the height of the jump", "Land in a crisp fifth"],
   ["adductors", "calves", "hip_flexors"], ["quadriceps", "core"],
   [K("fifth_demi", "third", d=0.4), K("degage_front", "third", d=0.12), K("air_cabriole", "third", d=0.18, dz=0.1), K("fifth_demi", "third", d=0.25, dz=0.15)], hero=2)
mv("ballonne", "Ballonné", "Ball-like / bouncing", "petit_allegro", 2,
   "A jump on one foot while the other leg extends and folds back to cou-de-pied, like a bouncing ball.",
   ["Extend and fold at the same time", "Land in fondu", "Travel slightly"],
   ["quadriceps", "calves", "hip_flexors"], ["hamstrings", "foot_intrinsics"],
   [K("fondu_coupe", "third", d=0.35), K("air_ballonne", "second", d=0.25, dx=-0.05), K("fondu_coupe", "third", d=0.25, dx=-0.1)], hero=1)
mv("ballotte", "Ballotté", "Tossed", "petit_allegro", 3,
   "A rocking jump: the legs alternately unfold to the front and back while the body sways like a boat.",
   ["Rock the body, not the hips", "Show both extensions", "Soft landings"],
   ["quadriceps", "hip_flexors", "glutes"], ["core", "erector_spinae"],
   [K("fondu_front", "third", d=0.4), K("air_fifth", "first", d=0.2), K("fondu_back", "third", "arabesque_lean", d=0.25), K("air_fifth", "first", d=0.2)], hero=0)
mv("emboite", "Emboîté", "Fitted together", "petit_allegro", 2,
   "Small alternating jumps from foot to foot, the working leg lifting to cou-de-pied or attitude front each time.",
   ["Change feet at the top of each jump", "Keep the knees open", "Light and springy"],
   ["calves", "quadriceps"], ["hip_flexors", "foot_intrinsics"],
   [K("fondu_coupe", "third", d=0.3), K("air_jete", "third", d=0.2), K("fondu_coupe", "third", d=0.2, m=True), K("air_jete", "third", d=0.2, m=True)], hero=0)
mv("pas_de_basque", "Pas de basque", "Basque step", "petit_allegro", 2,
   "A three-count travelling step: the leg describes a half circle, the weight springs across and closes.",
   ["Rond the leg low on the floor", "Spring across, don't walk", "Arms open and close with the step"],
   ["quadriceps", "deep_rotators"], ["calves", "core"],
   [K("fifth_demi", "first", d=0.4), K("tendu_front_plie", "first", d=0.3), K("tendu_side_plie", "second", d=0.3), K("coupe_front", "second", d=0.25, dx=-0.15), K("fifth_demi", "first", d=0.3, dz=0.15, dx=-0.15)], hero=2)
mv("temps_leve_arabesque", "Temps levé en arabesque", "Hop in arabesque", "petit_allegro", 2,
   "A hop on one leg holding the arabesque line.",
   ["Keep the back leg high", "Push from the supporting foot", "Land softly in fondu"],
   ["calves", "glutes", "quadriceps"], ["hamstrings", "erector_spinae"],
   [K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.4), K("air_arabesque", "arabesque1", "arabesque_lean", d=0.25), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.25)], hero=1)
mv("soubresaut", "Soubresaut", "Sudden spring", "petit_allegro", 2,
   "A jump from fifth to fifth without changing feet, travelling forward, the body slightly arched.",
   ["Hold the legs tightly together", "Arch the back slightly", "Travel forward"],
   ["calves", "adductors", "glutes"], ["erector_spinae", "core"],
   [K("fifth_demi", "first", d=0.4), K("air_fifth", "fourth", "cambre_back", d=0.25, dz=0.15), K("fifth_demi", "first", d=0.25, dz=0.25)], hero=1)
mv("gargouillade", "Gargouillade", "Gurgling", "petit_allegro", 4,
   "A pas de chat in which each leg performs a small rond de jambe in the air while rising.",
   ["Rond with the first leg as it lifts", "Second leg follows the same path", "Very quick and light"],
   ["hip_flexors", "hamstrings", "calves"], ["deep_rotators", "core"],
   [K("fifth_demi", "third", d=0.45), K("rja_side", "third", d=0.12), K("air_pas_de_chat", "third", d=0.18, dx=-0.15), K("fifth_demi", "third", d=0.25, dx=-0.2)], hero=2)

# ───────────────────────────── Grand allegro ─────────────────────────────
mv("grand_jete", "Grand jeté", "Big thrown leap", "grand_allegro", 3,
   "A big leap from one foot to the other with the legs in a full split in the air.",
   ["Throw the front leg, push off the back", "Split at the top of the jump", "Land in fondu, arabesque behind"],
   ["quadriceps", "hip_flexors", "glutes", "hamstrings"], ["calves", "core", "erector_spinae"],
   [K("tendu_front_plie", "first", d=0.5, dz=-0.3), K("air_split", "arabesque1", "arabesque_lean", d=0.35, dz=0.1), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.35, dz=0.4)], hero=1)
mv("saut_de_chat", "Saut de chat", "Cat's leap", "grand_allegro", 3,
   "A leaping split in which the front leg passes through développé (or a bent knee) before stretching.",
   ["Développé the front leg through the air", "Back leg stretched", "Lift the chest"],
   ["hip_flexors", "quadriceps", "glutes"], ["hamstrings", "calves", "core"],
   [K("tendu_front_plie", "first", d=0.5, dz=-0.3), K("air_saut_de_chat", "fourth", d=0.35, dz=0.1), K("arabesque_plie", "fourth", "arabesque_lean", d=0.35, dz=0.4)], hero=1)
mv("tour_jete", "Jeté entrelacé", "Interlaced leap (tour jeté)", "grand_allegro", 4,
   "A turning leap: the dancer throws one leg to the front, turns in the air and lands in arabesque on the same leg.",
   ["Brush through first, kicking high", "Turn the hips at the top", "Arabesque on landing"],
   ["hip_flexors", "glutes", "quadriceps"], ["obliques", "calves", "erector_spinae"],
   [K("tendu_back_plie", "first", d=0.5, yaw=0), K("battement_front", "fifth", d=0.15, yaw=0), K("air_split", "fifth", d=0.25, yaw=-90), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.3, yaw=-180, m=True)], hero=2, aka=["Tour jeté"])
mv("cabriole", "Cabriole", "Caper", "grand_allegro", 4,
   "The extended leg is beaten by the underneath leg in the air, front or back, before landing.",
   ["Throw the working leg high", "Beat the lower leg up to it", "Land on the beating leg in fondu"],
   ["adductors", "quadriceps", "hip_flexors"], ["calves", "glutes", "core"],
   [K("tendu_back_plie", "first", d=0.5), K("battement_front", "second", d=0.15), K("air_cabriole", "second", d=0.25), K("fondu_front", "second", d=0.3)], hero=2)
mv("grand_sissonne", "Grande sissonne", "Big scissor leap", "grand_allegro", 3,
   "A big sissonne from two feet travelling forward into a high arabesque.",
   ["Push off two feet together", "Open in the air", "Land on the front leg in arabesque"],
   ["glutes", "quadriceps", "hamstrings"], ["calves", "erector_spinae", "core"],
   [K("fifth_demi", "first", d=0.5, dz=-0.2), K("air_sissonne", "arabesque1", "arabesque_lean", d=0.35, lift=0.38, dz=0.1), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.35, dz=0.3)], hero=1)
mv("saut_de_basque", "Saut de basque", "Basque leap", "grand_allegro", 4,
   "A travelling turning jump: the dancer turns in the air with one leg in retiré and the other extended.",
   ["Step and throw the leg to the side", "Turn with the retiré tight", "Spot the direction of travel"],
   ["hip_flexors", "calves", "obliques"], ["quadriceps", "glutes", "core"],
   [K("tendu_side_plie", "second", d=0.5, yaw=0, dx=0.2), K("air_pas_de_chat", "fifth", d=0.3, yaw=-200, dx=-0.1), K("retire", "fifth", d=0.25, yaw=-360, dx=-0.3), K("fifth_demi", "second", d=0.3, yaw=-360, dx=-0.3)], hero=1)
mv("grand_pas_de_chat", "Grand pas de chat", "Big cat step (Russian)", "grand_allegro", 3,
   "A big travelling leap with the front leg in a high développé and the back leg in attitude.",
   ["Développé the front leg high", "Back leg bends in attitude", "Travel forward"],
   ["hip_flexors", "glutes", "quadriceps"], ["hamstrings", "calves", "core"],
   [K("tendu_front_plie", "first", d=0.5, dz=-0.3), K("air_biche", "fourth", d=0.35, dz=0.1), K("fondu_coupe", "third", d=0.35, dz=0.4)], hero=1)
mv("saut_de_biche", "Saut de biche", "Doe leap", "grand_allegro", 3,
   "A leap where the front leg is bent (attitude) while the back leg stretches long.",
   ["Front knee high", "Back leg fully extended", "Open the chest"],
   ["hip_flexors", "glutes"], ["quadriceps", "hamstrings", "calves"],
   [K("tendu_front_plie", "first", d=0.5, dz=-0.3), K("air_biche", "arabesque2", d=0.35, dz=0.1), K("arabesque_plie", "arabesque2", "arabesque_lean", d=0.35, dz=0.4)], hero=1)
mv("grand_assemble", "Grand assemblé", "Big assembled jump", "grand_allegro", 3,
   "A large travelling assemblé with a grand battement, joining the legs in the air.",
   ["Battement high, then join", "Spring from the supporting leg", "Land in fifth"],
   ["hip_flexors", "quadriceps", "calves"], ["glutes", "adductors"],
   [K("tendu_side_plie", "first", d=0.5), K("battement_side", "fifth", d=0.15), K("air_fifth", "fifth", d=0.25, lift=0.38, dx=-0.15), K("fifth_demi", "second", d=0.3, dx=-0.25)], hero=2)
mv("fouette_saute", "Fouetté sauté", "Whipped jump", "grand_allegro", 4,
   "The leg is thrown forward, the body whips around in the air and lands in arabesque facing the other way.",
   ["Battement front, then turn the hips", "Keep the leg at height through the whip", "Land in arabesque"],
   ["hip_flexors", "glutes", "obliques"], ["calves", "erector_spinae", "core"],
   [K("tendu_back_plie", "first", d=0.5, yaw=0), K("air_split", "fifth", d=0.3, yaw=-90), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.35, yaw=-180)], hero=1)
mv("saute_arabesque", "Sauté en arabesque", "Jump in arabesque", "grand_allegro", 2,
   "A big hop in arabesque, travelling forward with a sustained line.",
   ["Hold the arabesque in the air", "Push through the supporting foot", "Land in fondu"],
   ["calves", "glutes", "quadriceps"], ["hamstrings", "erector_spinae"],
   [K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.5), K("air_arabesque", "arabesque1", "arabesque_lean", d=0.3, lift=0.35, dz=0.15), K("arabesque_plie", "arabesque1", "arabesque_lean", d=0.3, dz=0.3)], hero=1)
mv("temps_leve_attitude", "Temps levé en attitude", "Hop in attitude", "grand_allegro", 3,
   "A hop holding the leg in attitude derrière, arm raised.",
   ["Knee lifted", "Chest open", "Soft landing"],
   ["glutes", "calves"], ["hamstrings", "erector_spinae", "quadriceps"],
   [K("arabesque_plie", "fourth", d=0.5), K("air_attitude", "fourth", d=0.3), K("arabesque_plie", "fourth", d=0.3)], hero=1)

# ───────────────────────────── Linking steps ─────────────────────────────
mv("pas_de_bourree", "Pas de bourrée dessous", "Bourrée step (under)", "linking", 1,
   "Three small steps — back, side, front — on demi-pointe, changing feet: the punctuation of ballet.",
   ["Step under, side, front", "Stay on demi-pointe", "Finish in a clean demi-plié"],
   ["calves", "foot_intrinsics"], ["quadriceps", "core"],
   [K("fifth_demi", "demi_second", d=0.4), K("coupe_back", "demi_second", d=0.2), K("fifth_releve", "demi_second", d=0.2), K("second_releve", "demi_second", d=0.2, dx=-0.1), K("fifth_demi", "demi_second", d=0.25, dx=-0.1, m=True)], hero=3)
mv("bourree_couru", "Pas de bourrée couru", "Running bourrée", "linking", 2,
   "Tiny, rapid steps on demi-pointe or pointe with the feet in a tight fifth, gliding across the floor.",
   ["Steps so small they are invisible", "Knees soft but legs together", "The torso floats"],
   ["calves", "adductors", "foot_intrinsics"], ["core", "tibialis"],
   [K("sous_sus", "second", d=0.4, dx=0), K("sous_sus", "second", d=1.0, dx=-0.4), K("sous_sus", "second", d=1.0, dx=0)], hero=0, aka=["Bourrée suivi"])
mv("balance", "Balancé", "Rocked / waltz step", "linking", 1,
   "A three-count waltz step swaying from side to side: step, ball change, step.",
   ["Down-up-up feeling", "Let the upper body sway", "Arms float through third"],
   ["calves", "quadriceps"], ["obliques", "core"],
   [K("tendu_side_plie", "third", "epaulement_l", d=0.4, dx=0), K("coupe_back", "third", "epaulement_l", d=0.25, dx=0.1), K("fondu_coupe", "third", "epaulement_l", d=0.25, dx=0.1), K("tendu_side_plie", "third", "epaulement_r", d=0.4, dx=0.1, m=True), K("coupe_back", "third", "epaulement_r", d=0.25, dx=0.0, m=True), K("fondu_coupe", "third", "epaulement_r", d=0.25, dx=0.0, m=True)], hero=0)
mv("chasse", "Chassé", "Chased", "linking", 1,
   "A sliding step where one foot 'chases' the other out of its position, often with a little spring.",
   ["Slide through demi-plié", "Second foot catches the first in the air", "Travel smoothly"],
   ["quadriceps", "adductors"], ["calves", "core"],
   [K("fifth_demi", "first", d=0.4), K("tendu_front_plie", "second", d=0.3, dz=0.1), K("air_fifth", "second", d=0.2, dz=0.25), K("fifth_demi", "first", d=0.25, dz=0.35)], hero=1)
mv("tombe", "Tombé", "Fallen", "linking", 1,
   "The dancer 'falls' onto the working leg in demi-plié, transferring weight forward, back or sideways.",
   ["Let the weight fall, but with control", "Land in fondu", "Lead with the extended leg"],
   ["quadriceps", "glutes"], ["calves", "core"],
   [K("degage_front", "first", d=0.4), K("tendu_front_plie", "second", d=0.4, dz=0.15), K("tendu_back_plie", "second", d=0.4, dz=0.3)], hero=1)
mv("pas_failli", "Pas failli", "Failing step", "linking", 2,
   "A sissonne whose back leg passes through first to the front — a quick, breathy preparation for big jumps.",
   ["Sweep the back leg through first", "Body twists slightly", "Lands in fourth demi-plié"],
   ["quadriceps", "hip_flexors"], ["obliques", "calves"],
   [K("fifth_demi", "first", d=0.4), K("air_sissonne", "arabesque2", "arabesque_lean", d=0.2), K("tendu_front_plie", "first", d=0.35, dz=0.2)], hero=1, aka=["Failli"])
mv("coupe_step", "Coupé", "Cut", "linking", 1,
   "A small step that 'cuts' one foot away by replacing it with the other — the link before jetés and turns.",
   ["Replace the foot quickly", "Land in fondu", "Keep the body still"],
   ["calves", "quadriceps"], ["foot_intrinsics"],
   [K("fondu_coupe", "bras_bas", d=0.35), K("coupe_releve", "bras_bas", d=0.2), K("fondu_coupe", "bras_bas", d=0.3, m=True)], hero=0)
mv("pique_arabesque", "Piqué arabesque", "Step into arabesque", "linking", 2,
   "Stepping directly onto a straight leg on demi-pointe or pointe, lifting into arabesque.",
   ["Step far onto a straight leg", "Back leg arrives with the step", "Lift through the chest"],
   ["calves", "glutes", "core"], ["hamstrings", "erector_spinae"],
   [K("tendu_front_plie", "first", d=0.5), K("arabesque_releve", "arabesque1", "arabesque_lean", d=0.35, dz=0.25), K("arabesque_releve", "arabesque1", "arabesque_lean", d=0.6, dz=0.25)], hero=1)
mv("pas_couru", "Pas couru", "Running step", "linking", 1,
   "A small running preparation (often three steps) gathering momentum for a big jump.",
   ["Run on the balls of the feet", "Body leads forward", "Accelerate into the jump"],
   ["calves", "quadriceps"], ["hip_flexors"],
   [K("fondu_back", "first", d=0.25, dz=0), K("fondu_back", "first", d=0.25, dz=0.15, m=True), K("fondu_back", "first", d=0.25, dz=0.3)], hero=0)
mv("glissade_precipitee", "Glissade précipitée", "Hurried glissade", "linking", 2,
   "A quick, low glissade used to link into big allegro.",
   ["Stay low", "No pause in fifth", "Spring straight into the next step"],
   ["quadriceps", "calves"], ["adductors"],
   [K("fifth_demi", "first", d=0.3), K("tendu_front_plie", "first", d=0.2, dz=0.1), K("fifth_demi", "first", d=0.2, dz=0.2)], hero=1)
mv("sous_sus_pointe", "Sous-sus sur les pointes", "Sous-sus on pointe", "pointe", 2,
   "A spring onto full pointe drawing both feet into a tight fifth under the body.",
   ["Pull up out of the shoes", "Thighs and heels crossed tight", "Hips over the boxes"],
   ["calves", "foot_intrinsics", "adductors"], ["core", "glutes"],
   [K("fifth_demi", "first", d=0.6), K("sous_sus", "fifth", d=0.3), K("sous_sus", "fifth", d=0.7)], hero=1)

# ───────────────────────────── Pointe ─────────────────────────────
mv("releve_pointe", "Relevé sur les pointes", "Rise onto pointe", "pointe", 2,
   "From demi-plié a quick spring onto full pointe, ankles fully over the box.",
   ["Over the box, not behind it", "Knees fully straight on top", "Lower through the foot"],
   ["calves", "foot_intrinsics", "tibialis"], ["core", "quadriceps"],
   [K("first_demi", "first", d=0.6), K("first_releve", "fifth", d=0.3), K("first_releve", "fifth", d=0.6)], hero=1)
mv("echappe_releve", "Échappé relevé", "Escape onto pointe", "pointe", 2,
   "From fifth demi-plié the feet spring apart to second on pointe, then close.",
   ["Both feet arrive together", "Pull the feet in as you close", "Change feet if asked"],
   ["calves", "foot_intrinsics", "adductors"], ["quadriceps", "core"],
   [K("fifth_demi", "first", d=0.5), K("second_releve", "second", d=0.3), K("second_releve", "second", d=0.4), K("fifth_demi", "first", d=0.3, m=True)], hero=2)
mv("retire_pointe", "Retiré sur la pointe", "Retiré on pointe", "pointe", 3,
   "Rising onto pointe on one leg while the working foot draws to the knee — the shape of a pointe pirouette.",
   ["Snatch the foot up", "Ankle over the box", "Hold, then roll down"],
   ["calves", "core", "foot_intrinsics"], ["hip_flexors", "deep_rotators"],
   [K("fifth_demi", "first", d=0.5), K("retire_releve", "fifth", d=0.3), K("retire_releve", "fifth", d=0.8)], hero=1)
mv("pique_pointe", "Piqué sur la pointe", "Stepping onto pointe", "pointe", 3,
   "Stepping directly onto the tip of a straight leg, the other foot lifting to cou-de-pied or retiré.",
   ["Step out, not up", "Straight supporting leg", "Close down through the foot"],
   ["calves", "foot_intrinsics", "quadriceps"], ["core", "tibialis"],
   [K("tendu_side_plie", "second", d=0.5), K("coupe_releve", "first", d=0.3, dx=-0.15), K("coupe_releve", "first", d=0.5, dx=-0.15)], hero=1)
mv("bourree_pointe", "Bourrée sur les pointes", "Bourrée on pointe", "pointe", 3,
   "Rapid shimmering steps on pointe — the swan's glide across the lake.",
   ["Tiny steps from the knees down", "Upper body completely calm", "Weight up over the boxes"],
   ["calves", "foot_intrinsics", "adductors"], ["core", "tibialis"],
   [K("sous_sus", "allonge", d=0.4, dx=0), K("sous_sus", "allonge", d=1.2, dx=-0.5), K("sous_sus", "allonge", d=1.2, dx=0)], hero=0)
mv("fouette_pointe", "Fouettés sur les pointes", "Fouettés on pointe", "pointe", 4,
   "The 32 fouettés of Swan Lake's Black Swan: whipping turns on pointe.",
   ["Plié every revolution", "Whip from the hip", "Spot the front"],
   ["calves", "hip_flexors", "core"], ["glutes", "foot_intrinsics", "obliques"],
   [K("seconde_plie", "second", d=0.35, yaw=0), K("retire_releve", "first", d=0.25, yaw=-180), K("retire_releve", "first", d=0.2, yaw=-360), K("seconde_plie", "second", d=0.2, yaw=-360)], hero=1)
mv("pas_de_cheval", "Pas de cheval", "Horse's step", "pointe", 2,
   "The working foot paws the floor like a horse: through cou-de-pied to a small extended point.",
   ["Lift through cou-de-pied", "Extend to a gentle point", "Precise, delicate"],
   ["foot_intrinsics", "calves"], ["hip_flexors", "tibialis"],
   [K("fifth", "first", d=0.4), K("coupe_front", "first", d=0.3), K("tendu_front", "first", d=0.3), K("fifth", "first", d=0.3)], hero=2)
mv("sus_sous_promenade", "Détourné", "Turned aside", "pointe", 2,
   "A half or full pivot in sous-sus on pointe, changing the front foot.",
   ["Stay tight in sous-sus", "Turn towards the back foot", "Finish with the other foot front"],
   ["calves", "adductors"], ["core", "obliques"],
   [K("sous_sus", "fifth", d=0.4, yaw=0), K("sous_sus", "fifth", d=0.6, yaw=-180), K("sous_sus", "fifth", d=0.6, yaw=-360), K("fifth_demi", "bras_bas", d=0.4, yaw=-360, m=True)], hero=1)


# ───────────────────────────── validation & output ─────────────────────────────
def validate() -> list[str]:
    errors = []
    ids = set()
    cats = {c[0] for c in CATEGORIES}
    for m in M:
        if m["id"] in ids:
            errors.append(f"duplicate id {m['id']}")
        ids.add(m["id"])
        if m["category"] not in cats:
            errors.append(f"{m['id']}: bad category {m['category']}")
        for mus in m["muscles"]["primary"] + m["muscles"]["secondary"]:
            if mus not in MUSCLES:
                errors.append(f"{m['id']}: unknown muscle {mus}")
        for k in m["animation"]["keys"]:
            if k["l"] not in LEGS: errors.append(f"{m['id']}: unknown legs pose {k['l']}")
            if k["a"] not in ARMS: errors.append(f"{m['id']}: unknown arms pose {k['a']}")
            if k["t"] not in TORSO: errors.append(f"{m['id']}: unknown torso pose {k['t']}")
            if k["d"] <= 0: errors.append(f"{m['id']}: non-positive duration")
        if not 0 <= m["animation"]["hero"] < len(m["animation"]["keys"]):
            errors.append(f"{m['id']}: hero index out of range")
    return errors


def check_pose_names() -> list[str]:
    """Cross-check every pose name against poses.json (generated by build_poses.py)."""
    f = ROOT / "ios/BalletDairy/Resources/poses.json"
    if not f.exists():
        return [f"missing {f} — run build_poses.py first"]
    poses = json.loads(f.read_text())
    errs = []
    for section, names in (("legs", LEGS), ("arms", ARMS), ("torso", TORSO)):
        for n in sorted(names - set(poses[section])):
            errs.append(f"poses.json missing {section} pose '{n}'")
    return errs


def main() -> int:
    errs = validate() + check_pose_names()
    if errs:
        print("\n".join(errs)); return 1
    payload = {
        "version": 1,
        "categories": [{"id": c, "name": n, "blurb": b} for c, n, b in CATEGORIES],
        "movements": M,
    }
    for out in (ROOT / "backend/data/movements.json", ROOT / "ios/BalletDairy/Resources/movements.json"):
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=1))
    by_cat = {}
    for m in M:
        by_cat[m["category"]] = by_cat.get(m["category"], 0) + 1
    print(f"wrote {len(M)} movements", by_cat)
    return 0


if __name__ == "__main__":
    sys.exit(main())
