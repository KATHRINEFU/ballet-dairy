#!/usr/bin/env python3
"""
Pose parts for the Ballet Diary 3D dancer, plus a forward-kinematics model that
mirrors ios/BalletDairy/Features/Dancer/Skeleton.swift exactly.

Run:  python3 backend/scripts/build_poses.py [--preview out.png]

Conventions (all angles in degrees, dancer faces +Z towards the audience,
+X is the dancer's LEFT, +Y is up):
  joint local rotation R = Rz(z) · Rx(x) · Ry(y)   (y applied first)
  hips:      x<0 lifts the leg to the front, x>0 to the back,
             y is turnout (left leg +, right leg −),
             z>0 swings towards +X (left leg outward / right leg inward)
  knees:     x>0 bends
  ankles:    x>0 points the foot, x<0 flexes
  spine etc: x>0 bends forward, z<0 bends towards the dancer's left, y twists
The right leg is the working leg; the left supports.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]

# ── skeleton (must match Skeleton.swift) ──
JOINTS = [
    # name, parent, offset
    ("pelvis", None, (0, 0, 0)),
    ("l_hip", "pelvis", (0.09, -0.06, 0)), ("l_knee", "l_hip", (0, -0.44, 0)), ("l_ankle", "l_knee", (0, -0.42, 0)),
    ("r_hip", "pelvis", (-0.09, -0.06, 0)), ("r_knee", "r_hip", (0, -0.44, 0)), ("r_ankle", "r_knee", (0, -0.42, 0)),
    ("spine", "pelvis", (0, 0.10, 0)), ("chest", "spine", (0, 0.22, 0)), ("neck", "chest", (0, 0.20, 0)),
    ("head", "neck", (0, 0.07, 0)),
    ("l_shoulder", "chest", (0.17, 0.16, 0)), ("l_elbow", "l_shoulder", (0, -0.27, 0)), ("l_wrist", "l_elbow", (0, -0.24, 0)),
    ("r_shoulder", "chest", (-0.17, 0.16, 0)), ("r_elbow", "r_shoulder", (0, -0.27, 0)), ("r_wrist", "r_elbow", (0, -0.24, 0)),
]
MARKERS = {  # name: (parent joint, local offset)
    "l_heel": ("l_ankle", (0, -0.06, -0.04)), "l_toe": ("l_ankle", (0, -0.055, 0.17)),
    "r_heel": ("r_ankle", (0, -0.06, -0.04)), "r_toe": ("r_ankle", (0, -0.055, 0.17)),
    "head_top": ("head", (0, 0.22, 0)),
    "l_hand": ("l_wrist", (0, -0.08, 0)), "r_hand": ("r_wrist", (0, -0.08, 0)),
}
STANDING_ROOT_Y = 0.98
T = 50.0  # turnout


def rx(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    a = math.radians(a); c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def local_rot(e):
    x, y, z = e
    return rz(z) @ rx(x) @ ry(y)


def fk(angles: dict, root=(0, STANDING_ROOT_Y, 0), yaw=0.0):
    R = {}; P = {}
    for name, parent, off in JOINTS:
        lr = local_rot(angles.get(name, (0, 0, 0)))
        if parent is None:
            R[name] = ry(yaw) @ lr; P[name] = np.array(root, float)
        else:
            R[name] = R[parent] @ lr; P[name] = P[parent] + R[parent] @ np.array(off, float)
    for m, (parent, off) in MARKERS.items():
        P[m] = P[parent] + R[parent] @ np.array(off, float)
    return P


# ── leg helpers (s = +1 left, −1 right) ──
def leg(s, front=0.0, out=0.0, knee=0.0, ankle=0.0, turn=T):
    """front>0 lifts forward, <0 backward; out>0 away from the centre line."""
    p = "l" if s > 0 else "r"
    return {f"{p}_hip": [-front, s * turn, s * out], f"{p}_knee": [knee, 0, 0], f"{p}_ankle": [ankle, 0, 0]}


def plie(s, a, front=0.0, out=0.0, ankle_extra=0.0, turn=T):
    """bend the knee by `a` along the turned-out direction"""
    rad = math.radians(turn)
    return leg(s, front + a * math.cos(rad), out + a * math.sin(rad), knee=2 * a, ankle=-a + ankle_extra, turn=turn)


def both(*parts):
    d = {}
    for p in parts: d.update(p)
    return d


L, R = 1, -1
RELEVE = 72
POINT = 70

# supporting leg variations
# the supporting leg angles in slightly so the foot sits under the body's centre
SUP = leg(L, out=-5.5)
SUP_PLIE = plie(L, 28, out=-5.5)
SUP_RELEVE = leg(L, out=-5.5, ankle=RELEVE)


def solve_toe_on_floor(make, lo=0.0, hi=80.0, support="left"):
    """binary-search a gesture angle so the working toe just touches the floor"""
    def toe_gap(a):
        ang = make(a); P = fk(ang)
        sup = [P["l_heel"][1], P["l_toe"][1]] if support == "left" else [P["l_heel"][1], P["l_toe"][1], P["r_heel"][1]]
        return P["r_toe"][1] - min(sup)
    for _ in range(40):
        mid = (lo + hi) / 2
        if toe_gap(mid) > 0: hi = mid
        else: lo = mid
    return round((lo + hi) / 2, 1)


def tendu(direction, sup=SUP, extra=0.0):
    def make(a):
        if direction == "front": w = leg(R, front=a, out=-4, ankle=POINT)
        elif direction == "side": w = leg(R, out=a, ankle=POINT)
        else: w = leg(R, front=-a, out=-4, ankle=POINT)
        return both(sup, w)
    a = solve_toe_on_floor(make) + extra
    return {**make(a), "_angle": a}


def mirror(d):
    """right-leg joint dict -> the same gesture on the left"""
    out = {}
    for k, (x, y, z) in d.items():
        k2 = ("l_" + k[2:]) if k.startswith("r_") else ("r_" + k[2:]) if k.startswith("l_") else k
        out[k2] = [x, -y, -z]
    return out


def strip(d):
    return {k: v for k, v in d.items() if not k.startswith("_")}


LEGS = {}


def legs(name, angles, support="both", lift=0.0):
    LEGS[name] = {"support": support, "lift": lift, "joints": strip(angles)}


# feet positions
legs("first", both(leg(L, out=-2.5), leg(R, out=-2.5)))
legs("second", both(leg(L, out=11), leg(R, out=11)))
legs("third", both(leg(L, front=-3, out=-3), leg(R, front=4, out=-3.5)))
legs("fourth", both(leg(L, front=-11, out=-3), leg(R, front=16, out=-3)))
legs("fifth", both(leg(L, front=-4, out=-6, turn=55), leg(R, front=5, out=-6, turn=55)))
# pliés
legs("first_demi", both(plie(L, 30, out=-2.5), plie(R, 30, out=-2.5)))
legs("first_grand", both(plie(L, 62, out=-2.5, ankle_extra=40), plie(R, 62, out=-2.5, ankle_extra=40)))
legs("second_demi", both(plie(L, 30, out=11), plie(R, 30, out=11)))
legs("second_grand", both(plie(L, 52, out=13), plie(R, 52, out=13)))
legs("fourth_demi", both(plie(L, 26, front=-11, out=-3), plie(R, 26, front=16, out=-3)))
legs("fifth_demi", both(plie(L, 28, front=-4, out=-6, turn=55), plie(R, 28, front=5, out=-6, turn=55)))
legs("fourth_lunge", both(leg(L, front=-22, out=-3), plie(R, 34, front=18, out=-3)))
# relevés
legs("first_releve", both(leg(L, out=-2.5, ankle=RELEVE), leg(R, out=-2.5, ankle=RELEVE)))
legs("second_releve", both(leg(L, out=10, ankle=RELEVE), leg(R, out=10, ankle=RELEVE)))
legs("fifth_releve", both(leg(L, front=-4, out=-6, turn=55, ankle=RELEVE), leg(R, front=5, out=-6, turn=55, ankle=RELEVE)))
legs("sous_sus", both(leg(L, front=-3, out=-8, turn=55, ankle=78), leg(R, front=4, out=-8, turn=55, ankle=78)))
# tendus & dégagés
for d in ("front", "side", "back"):
    legs(f"tendu_{d}", tendu(d), "left")
    legs(f"tendu_{d}_plie", tendu(d, SUP_PLIE), "left")
    t = tendu(d)
    if d == "front": g = leg(R, front=t["_angle"] + 22, out=-4, ankle=POINT)
    elif d == "side": g = leg(R, out=t["_angle"] + 22, ankle=POINT)
    else: g = leg(R, front=-(t["_angle"] + 20), out=-4, ankle=POINT)
    legs(f"degage_{d}", both(SUP, g), "left")
def solve_gesture(sup, toe_target, knee_target, x0=(30, 40, 90), ankle=POINT, knee_w=0.35):
    """find (front, out, knee) so the working toe reaches a spot on the supporting leg
    while the working knee opens to the side — e.g. retiré, sur le cou-de-pied."""
    from scipy.optimize import minimize

    def pts(v):
        P = fk(both(sup, leg(R, front=v[0], out=v[1], knee=v[2], ankle=ankle)))
        return P

    def cost(v):
        P = pts(v)
        tt = P[toe_target[0]] + np.array(toe_target[1])
        kt = np.array(knee_target(P))
        return np.sum((P["r_toe"] - tt) ** 2) + knee_w * np.sum((P["r_knee"] - kt) ** 2) + 1e-6 * np.sum(np.array(v) ** 2)

    res = minimize(cost, x0, method="Nelder-Mead", options={"xatol": 0.05, "fatol": 1e-8, "maxiter": 4000})
    f, o, k = (round(float(x), 1) for x in res.x)
    return leg(R, front=f, out=o, knee=k, ankle=ankle)


# cou-de-pied family (solved so the toe really wraps the supporting ankle)
COUPE_F = solve_gesture(SUP, ("l_ankle", (-0.01, 0.03, 0.06)), lambda P: (P["r_hip"][0] - 0.22, P["l_knee"][1] - 0.1, 0.12))
COUPE_B = solve_gesture(SUP, ("l_ankle", (-0.01, 0.05, -0.07)), lambda P: (P["r_hip"][0] - 0.2, P["l_knee"][1] - 0.1, 0.02), x0=(10, 30, 90), knee_w=0.12)
legs("coupe_front", both(SUP, COUPE_F), "left")
legs("coupe_back", both(SUP, COUPE_B), "left")
legs("coupe_flex", both(SUP, {**COUPE_F, "r_ankle": [-12, 0, 0]}), "left")
legs("coupe_releve", both(SUP_RELEVE, COUPE_F), "left")
legs("frappe_side", both(SUP, leg(R, out=30, ankle=POINT)), "left")
legs("frappe_front", both(SUP, leg(R, front=30, out=-3, ankle=POINT)), "left")
FONDU_C = solve_gesture(SUP_PLIE, ("l_ankle", (-0.01, 0.04, 0.06)), lambda P: (P["r_hip"][0] - 0.24, P["l_knee"][1] - 0.05, 0.16))
legs("fondu_coupe", both(SUP_PLIE, FONDU_C), "left")
legs("fondu_front", both(SUP_PLIE, leg(R, front=45, out=-3, ankle=POINT)), "left")
legs("fondu_side", both(SUP_PLIE, leg(R, out=45, ankle=POINT)), "left")
legs("fondu_back", both(SUP_PLIE, leg(R, front=-40, out=-3, ankle=POINT)), "left")
# retiré
RETIRE = solve_gesture(SUP, ("l_knee", (-0.02, -0.02, 0.06)), lambda P: (P["r_hip"][0] - 0.38, P["l_knee"][1] + 0.12, 0.10), x0=(40, 60, 120), knee_w=0.12)
legs("retire", both(SUP, RETIRE), "left")
legs("retire_releve", both(SUP_RELEVE, RETIRE), "left")
legs("retire_plie", both(SUP_PLIE, RETIRE), "left")
# extensions
legs("developpe_front", both(SUP, leg(R, front=88, out=-2, ankle=POINT)), "left")
legs("developpe_side", both(SUP, leg(R, out=88, front=8, ankle=POINT)), "left")
legs("developpe_back", both(SUP, leg(R, front=-80, out=4, ankle=POINT)), "left")
legs("attitude_front", both(SUP, leg(R, front=78, out=10, knee=55, ankle=POINT)), "left")
ATT_B = leg(R, front=-78, out=22, knee=78, ankle=POINT)
legs("attitude_back", both(SUP, ATT_B), "left")
legs("attitude_back_releve", both(SUP_RELEVE, ATT_B), "left")
ARAB = leg(R, front=-85, out=5, ankle=POINT)
legs("arabesque", both(SUP, ARAB), "left")
legs("arabesque_releve", both(SUP_RELEVE, ARAB), "left")
legs("arabesque_plie", both(SUP_PLIE, ARAB), "left")
legs("penche_leg", both(SUP, leg(R, front=-150, out=4, ankle=POINT)), "left")
legs("battement_front", both(SUP, leg(R, front=118, out=-2, ankle=POINT)), "left")
legs("battement_side", both(SUP, leg(R, out=118, front=10, ankle=POINT)), "left")
legs("battement_back", both(SUP, leg(R, front=-95, out=4, ankle=POINT)), "left")
legs("rja_side", both(SUP, leg(R, out=48, ankle=POINT)), "left")
legs("rja_in", both(SUP, leg(R, out=48, knee=75, ankle=POINT)), "left")
legs("seconde_plie", both(SUP_PLIE, leg(R, out=88, front=8, ankle=POINT)), "left")
legs("seconde_releve", both(SUP_RELEVE, leg(R, out=88, front=8, ankle=POINT)), "left")
# in the air
AIR = 0.30
legs("air_first", both(leg(L, out=-2, ankle=78), leg(R, out=-2, ankle=78)), "air", AIR)
legs("air_fifth", both(leg(L, front=-3, out=-6, turn=55, ankle=78), leg(R, front=4, out=-6, turn=55, ankle=78)), "air", AIR)
legs("air_second", both(leg(L, out=14, ankle=78), leg(R, out=14, ankle=78)), "air", AIR)
legs("air_tour", both(leg(L, front=-3, out=-8, turn=55, ankle=80), leg(R, front=4, out=-8, turn=55, ankle=80)), "air", 0.38)
legs("air_split", both(leg(R, front=88, out=-2, ankle=78), leg(L, front=-88, out=2, ankle=78)), "air", 0.34)
legs("air_saut_de_chat", both(leg(R, front=95, out=-2, knee=18, ankle=78), leg(L, front=-80, out=2, ankle=78)), "air", 0.34)
legs("air_biche", both(leg(R, front=80, out=6, knee=80, ankle=78), leg(L, front=-82, out=2, ankle=78)), "air", 0.33)
legs("air_cabriole", both(leg(R, front=62, out=-2, ankle=80), leg(L, front=48, out=-2, ankle=80)), "air", 0.36)
legs("air_pas_de_chat", both(RETIRE, mirror(RETIRE)), "air", 0.34)
legs("air_sissonne", both(leg(L, front=18, out=-2, ankle=78), leg(R, front=-65, out=4, ankle=78)), "air", 0.32)
legs("air_jete", both(leg(L, ankle=78), COUPE_B), "air", AIR)
legs("air_arabesque", both(leg(L, ankle=78), leg(R, front=-85, out=5, ankle=78)), "air", AIR)
legs("air_attitude", both(leg(L, ankle=78), leg(R, front=-78, out=22, knee=78, ankle=78)), "air", AIR)
legs("air_ballonne", both(leg(L, ankle=78), leg(R, out=45, ankle=78)), "air", AIR)


# ── arms (shoulder, elbow) ──
def arm(s, front=0.0, out=0.0, elbow_fwd=0.0, elbow_in=0.0, twist=0.0):
    p = "l" if s > 0 else "r"
    return {f"{p}_shoulder": [-front, s * twist, s * out], f"{p}_elbow": [-elbow_fwd, 0, -s * elbow_in]}


A_BAS = lambda s: arm(s, front=10, out=8, elbow_fwd=18, elbow_in=22)
A_FIRST = lambda s: arm(s, front=68, out=14, elbow_fwd=8, elbow_in=42)
A_SECOND = lambda s: arm(s, front=18, out=78, elbow_fwd=14)
A_FIFTH = lambda s: arm(s, front=22, out=158, elbow_fwd=0, elbow_in=-34)
A_ALLONGE = lambda s: arm(s, front=16, out=76)
A_DEMI = lambda s: arm(s, front=14, out=40, elbow_fwd=10, elbow_in=6)
A_BARRE = lambda s: arm(s, front=32, out=40, elbow_fwd=30, elbow_in=-30)

ARMS = {
    "bras_bas": both(A_BAS(L), A_BAS(R)),
    "first": both(A_FIRST(L), A_FIRST(R)),
    "second": both(A_SECOND(L), A_SECOND(R)),
    "third": both(A_SECOND(L), A_FIRST(R)),
    "fourth": both(A_SECOND(L), A_FIFTH(R)),
    "fifth": both(A_FIFTH(L), A_FIFTH(R)),
    "allonge": both(A_ALLONGE(L), A_ALLONGE(R)),
    "demi_second": both(A_DEMI(L), A_DEMI(R)),
    "arabesque1": both(arm(L, front=100, out=6, elbow_fwd=2), arm(R, front=-8, out=74)),
    "arabesque2": both(arm(R, front=100, out=4, elbow_fwd=2), arm(L, front=-22, out=62)),
    "barre": both(A_BARRE(L), A_SECOND(R)),
    "barre_bas": both(A_BARRE(L), A_BAS(R)),
    "barre_first": both(A_BARRE(L), A_FIRST(R)),
    "barre_fifth": both(A_BARRE(L), A_FIFTH(R)),
    "reverence": both(arm(L, front=28, out=40), arm(R, front=28, out=40)),
}

TORSO = {
    "neutral": {},
    "cambre_back": {"spine": [-10, 0, 0], "chest": [-22, 0, 0], "neck": [-8, 0, 0], "head": [-12, 0, 0]},
    "cambre_forward": {"spine": [60, 0, 0], "chest": [28, 0, 0], "neck": [10, 0, 0], "head": [12, 0, 0]},
    "cambre_side": {"spine": [0, 0, -10], "chest": [0, 0, -22], "neck": [0, 0, -6], "head": [0, 0, -8]},
    "arabesque_lean": {"spine": [14, 0, 0], "chest": [-6, 0, 0], "head": [-10, 0, 0]},
    "penche": {"spine": [58, 0, 0], "chest": [16, 0, 0], "head": [-14, 0, 0]},
    "epaulement_r": {"chest": [0, 16, 0], "neck": [0, 6, 0], "head": [-4, 16, 8]},
    "epaulement_l": {"chest": [0, -16, 0], "neck": [0, -6, 0], "head": [-4, -16, -8]},
    "bow": {"spine": [24, 0, 0], "chest": [10, 0, 0], "head": [16, 0, 0]},
}


def compose(l, a="bras_bas", t="neutral"):
    ang = {}
    ang.update(LEGS[l]["joints"]); ang.update(ARMS[a])
    for k, v in TORSO[t].items(): ang[k] = v
    return ang


def ground_root(l, a="bras_bas", t="neutral", yaw=0.0):
    """root position so the supporting foot sits on the floor (y=0)"""
    ang = compose(l, a, t)
    sup = LEGS[l]["support"]
    if sup == "air":
        return (0.0, STANDING_ROOT_Y + LEGS[l]["lift"], 0.0)
    P = fk(ang, yaw=yaw)
    feet = ["l_heel", "l_toe"] + (["r_heel", "r_toe"] if sup == "both" else [])
    low = min(P[f][1] for f in feet)
    return (0.0, STANDING_ROOT_Y - low, 0.0)


def check() -> list[str]:
    """physical sanity checks on key poses"""
    msgs = []
    def P(l, a="bras_bas", t="neutral"):
        root = ground_root(l, a, t); return fk(compose(l, a, t), root=root)
    p = P("retire"); d = np.linalg.norm(p["r_toe"] - p["l_knee"])
    msgs.append(f"retiré: toe→supporting knee {d:.3f} m")
    p = P("coupe_front"); d = np.linalg.norm(p["r_toe"] - p["l_ankle"])
    msgs.append(f"coupé front: toe→supporting ankle {d:.3f} m")
    p = P("coupe_back"); d = np.linalg.norm(p["r_toe"] - p["l_ankle"])
    msgs.append(f"coupé back: toe→supporting ankle {d:.3f} m")
    for n in ("first_demi", "first_grand", "second_grand", "fifth"):
        p = P(n); msgs.append(f"{n}: pelvis y {p['pelvis'][1]:.2f}, heels y {p['l_heel'][1]:.3f}/{p['r_heel'][1]:.3f}, ankles x {p['l_ankle'][0]:.3f}/{p['r_ankle'][0]:.3f}")
    p = P("first_releve"); msgs.append(f"relevé pelvis rise {p['pelvis'][1] - STANDING_ROOT_Y:.3f} m")
    p = P("first", "barre"); msgs.append(f"barre hand at {np.round(p['l_hand'], 2)}")
    p = P("first", "fifth"); msgs.append(f"fifth arms hands {np.round(p['l_hand'], 2)} {np.round(p['r_hand'], 2)} head_top {np.round(p['head_top'], 2)}")
    p = P("first", "first"); msgs.append(f"first arms hands {np.round(p['l_hand'], 2)} {np.round(p['r_hand'], 2)}")
    return msgs


def preview(path, names):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    bones = [("pelvis", "l_hip"), ("pelvis", "r_hip"), ("l_hip", "l_knee"), ("l_knee", "l_ankle"), ("l_heel", "l_toe"),
             ("r_hip", "r_knee"), ("r_knee", "r_ankle"), ("r_heel", "r_toe"), ("pelvis", "spine"), ("spine", "chest"),
             ("chest", "neck"), ("neck", "head"), ("chest", "l_shoulder"), ("l_shoulder", "l_elbow"), ("l_elbow", "l_wrist"),
             ("l_wrist", "l_hand"), ("chest", "r_shoulder"), ("r_shoulder", "r_elbow"), ("r_elbow", "r_wrist"), ("r_wrist", "r_hand")]
    cols = 6; rows = math.ceil(len(names) / cols)
    fig, axes = plt.subplots(rows, cols * 2, figsize=(cols * 3.2, rows * 2.6))
    axes = np.array(axes).reshape(rows, cols * 2)
    for ax in axes.flat: ax.axis("off")
    for i, spec in enumerate(names):
        l, a, t = (spec + (None, None))[:3] if isinstance(spec, tuple) else (spec, None, None)
        a = a or ("barre" if LEGS[l]["support"] != "air" else "fifth"); t = t or "neutral"
        root = ground_root(l, a, t); p = fk(compose(l, a, t), root=root)
        for j, (ix, iy, title) in enumerate(((0, 1, "front"), (2, 1, "side"))):
            ax = axes[i // cols, (i % cols) * 2 + j]
            for b0, b1 in bones:
                c = "#c0587a" if b0.startswith("r_") or b1.startswith("r_") else "#3b2f35"
                ax.plot([p[b0][ix], p[b1][ix]], [p[b0][iy], p[b1][iy]], c=c, lw=2)
            hc = p["head"] + np.array([0, 0.11, 0])
            ax.add_patch(plt.Circle((hc[ix], hc[iy]), 0.1, fill=False, color="#3b2f35"))
            ax.axhline(0, color="#aaa", lw=0.8)
            ax.set_xlim(-1.1, 1.1); ax.set_ylim(-0.05, 2.3); ax.set_aspect("equal")
            ax.set_title(f"{l}/{a}" if j == 0 else "side (+z→)", fontsize=7)
    plt.tight_layout(); plt.savefig(path, dpi=70)


def main():
    out = {
        "version": 1,
        "standingRootY": STANDING_ROOT_Y,
        "legs": LEGS,
        "arms": {k: {"joints": v} for k, v in ARMS.items()},
        "torso": {k: {"joints": v} for k, v in TORSO.items()},
    }
    p = ROOT / "ios/BalletDairy/Resources/poses.json"
    p.write_text(json.dumps(out, indent=1))
    (ROOT / "backend/data/poses.json").write_text(json.dumps(out, indent=1))
    print(f"wrote {len(LEGS)} legs, {len(ARMS)} arms, {len(TORSO)} torso poses")
    for m in check(): print("  ", m)
    if "--preview" in sys.argv:
        names = sys.argv[sys.argv.index("--preview") + 2:] or list(LEGS)
        preview(sys.argv[sys.argv.index("--preview") + 1], names)


if __name__ == "__main__":
    main()
