# Scoring

VANTA's score answers one question: *how well did this attempt at this drill go, by
the rules this drill declared?* Everything here is computed from events the
simulation already recorded, in integer arithmetic, from a seeded run.

## What the score is not

- It is **not a rank**, and not comparable across scenarios. 900 in `wide_flick_60`
  and 900 in `smooth_tracking_30` are different units doing different jobs.
- It is **not a measure of skill in any game**. No claim is made that a VANTA score
  predicts performance in a specific title, and none could be verified.
- It is **not a composite "aim score"**. There is no hidden weighting. The results
  screen shows the breakdown by term, in the order of what moved the number most.

Use the personal best and the history trend to judge improvement.

## Terms

Every scenario declares its own `scoring` block. Unset terms are zero, and a term that
is zero never contributes.

| Term | Default | Applied when |
| --- | --- | --- |
| `hit_points` | 0 | Each accepted hit on a counted region |
| `kill_points` | 100 | Each eliminated target |
| `headshot_points` | 50 | Added to a hit or elimination flagged as a headshot |
| `time_bonus_base` / `time_bonus_rate` | 0 / 0 | On elimination: `base − floor(time_to_kill × rate)`, never below 0 |
| `streak_bonus` / `streak_cap` | 0 / 10 | On elimination: `streak_bonus × min(streak, streak_cap)` |
| `miss_penalty` | 0 | Each shot that did not hit a target (including shots stopped by cover) |
| `expiry_penalty` | 0 | Each target that expired |
| `accuracy_bonus_rate` | 0 | Once, at the end: `round(accuracy_percent × rate / 100)` |
| `tracking_points_per_second` | 0 | Tracking drills: accumulated per simulation step while the crosshair is on a target |
| `tracking_off_target_penalty_per_second` | 0 | Tracking drills: same, while it is not |
| `score_floor` | 0 | Clamps the running total after penalties |

Cross-field checks reject the combinations that would break a drill: a scoring block
with no positive term is an **error**, and a positive `score_floor` is an **error**
(a floor above zero would hand out points for doing nothing). A block with
`kill_points > 0` but no miss or expiry penalty produces a **warning** that the drill
rewards spamming.

## Arithmetic rules

- Scores are integers. Tracking and accuracy bonuses are rounded once, at the moment
  they are applied, so two identical runs produce identical numbers.
- The floor is applied after penalties only. It never caps rewards.
- Time-to-kill is measured from the target's spawn to the shot that resolved it, on
  the simulation clock, not on frame boundaries.
- Secondary pellets of one trigger pull never award a second hit or a second kill:
  one trigger pull is one shot in every statistic and every term.

## Derived statistics

| Statistic | Definition |
| --- | --- |
| Accuracy | `hits / shots`, where `shots` are accepted trigger pulls. Refused pulls (reloading, empty magazine, moving when the drill requires standing still) are counted separately as `rejected_shots` and never as misses. |
| Misses | Shots that hit nothing, including shots stopped by cover. An expired target is **not** a miss: it is not a shot, and it is reported as `targets_expired`. |
| Headshot ratio | `headshots / hits` |
| Time to first hit | Spawn → first accepted hit on that target |
| Time to kill | Spawn → the hit that retired the target |
| Consistency | `100 − coefficient of variation × 166`, saturating at 60 % spread. Undefined below 5 kills (reported as 0 rather than as a perfect score) |
| Tracking ratio | Time on target over total tracked time |

## Pass and fail

The score is not a pass criterion. Each scenario may declare a `success` block
(`min_accuracy`, `min_score`, `max_average_time_to_kill`, `min_headshot_ratio`,
`min_targets`, `max_misses`, `min_consistency`), and a run passes only when every
requirement it declares is met.

A scenario with an empty `success` block is reported as **practice**, not as failed:
a drill with nothing to pass has not been failed.

`max_misses` in a success block uses the scenario's own failure counter — misses plus
expiries when `lifetime.counts_as_miss` is true — which is the same number the
fail-on-misses rule uses.

## Shipped scenarios

| Scenario | hit | kill | head | time bonus | streak | miss | expiry | accuracy | tracking |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- |
| `static_precision_60` | 0 | 100 | 50 | 250 − 35·ttk | 10 (cap 10) | 0 | 0 | 20 | — |
| `micro_flick_60` | 0 | 100 | 50 | 200 − 60·ttk | 10 | 5 | 0 | 20 | — |
| `wide_flick_60` | 0 | 100 | 50 | 260 − 55·ttk | 15 | 5 | 0 | 15 | — |
| `dynamic_clicking_60` | 15 | 100 | 50 | — | 10 | 3 | 0 | 20 | — |
| `movement_aim_60` | 0 | 100 | 50 | 200 − 40·ttk | 10 | 5 | 0 | 20 | — |
| `target_switching_45` | 0 | 110 | 50 | 200 − 45·ttk | 15 | 5 | 0 | 20 | — |
| `headshot_matrix_60` | 10 | 120 | 60 | — | 15 | 5 | 0 | 25 | — |
| `peek_lab_45` | 20 | 120 | 50 | — | 15 | 5 | 0 | 25 | — |
| `smooth_tracking_30` | 0 | 250 | 50 | — | 0 | 10 | 0 | 0 | +12 / −6 per second |
| `reactive_tracking_30` | 0 | 250 | 50 | — | 0 | 10 | 0 | 0 | +12 / −6 per second |

Tracking scenarios are scored by behaviour rather than by clicks: `kill_points` is a
bonus for holding the beam long enough to destroy a target, and almost all of the
score comes from time on target.

## Anti-farming review

- Every positive term is tied to something the player had to acquire: a hit, a kill,
  a streak of kills, or time spent on target.
- Spraying is always a loss: more shots cannot raise accuracy, they raise spread, and
  the scenarios that allow infinite ammo pair it with a miss penalty.
- Pre-aiming a fixed spot is not a strategy: spawn positions are randomised within the
  scenario's declared region, and every scenario states its own seed behaviour.
- The time bonus rewards *resolution*, not volume — it is a decaying function of
  time-to-kill, so a faster kill is always worth more than a slower one.
- Streak bonuses are capped, so one lucky run cannot run away with the score.

## Verification

`tests/test_scenario_runtime.gd` checks the score end to end: the same seed produces
the same score, body hits in a head-only drill award nothing, expiry penalties never
take the score below the floor, and a drill's success criteria are met only when its
requirements are. `tests/test_content.gd` checks that every shipped scenario passes
the scoring validators.
