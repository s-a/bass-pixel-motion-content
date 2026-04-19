#import <engine::bpm_kernel_bindings>

// ─────────────────────────────────────────────────────────────────────
//  Atmospheric Particles – Realistic snow simulation via FluxFlow
//
//  Architecture:
//    ff_init   → seed each particle, stagger above screen
//    ff_update → simulate fall with dt, drift, wind, turbulence
//    ff_vs     → billboard quad per particle
//    ff_fs     → soft-disc fragment
//
//  State layout (4 × vec4 = 64 bytes per particle):
//    pos_age.x       = Y position (negative = above screen, 0–1 = visible)
//    pos_age.y       = accumulated fall time (for wobble phase)
//    pos_age.z       = rest timer (< 0 = resting countdown, >= 0 = falling)
//    pos_age.w       = cycle count (increments on each respawn)
//    velocity_life.x = layer (0 = far, 1 = mid, 2 = near)
//    velocity_life.y = initial X [0..1]
//    velocity_life.z = display X [0..1] (computed each frame)
//    velocity_life.w = (unused)
//    style.x         = active mask (0 or 1)
//    style.y         = visible mask (0 or 1)
//    style.z         = (unused)
//    style.w         = (unused)
//    seed_data       = persistent random identity (s0, s1, s2, s3)
// ─────────────────────────────────────────────────────────────────────

const TAU: f32 = 6.28318530718;

struct ParticleState {
  pos_age: vec4<f32>,
  velocity_life: vec4<f32>,
  style: vec4<f32>,
  seed_data: vec4<f32>,
}

struct RenderOut {
  @builtin(position) position: vec4<f32>,
  @location(0) local_uv: vec2<f32>,
  @location(1) alpha_scale: f32,
  @location(2) tint: vec3<f32>,
  @location(3) softness_bias: f32,
}

@group(0) @binding(1)
var<storage, read> state_in: array<ParticleState>;

@group(0) @binding(2)
var<storage, read_write> state_out: array<ParticleState>;


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Hash & Noise  (identical to reference c3c11bb for consistent look)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn ap_hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn ap_hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn ap_value_noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(ap_hash21(i), ap_hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(ap_hash21(i + vec2<f32>(0.0, 1.0)), ap_hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y,
  );
}

fn ap_fbm(p: vec2<f32>) -> f32 {
  var v = ap_value_noise(p) * 0.5;
  v += ap_value_noise(p * 2.03 + vec2<f32>(1.7, 3.1)) * 0.3;
  v += ap_value_noise(p * 4.11 + vec2<f32>(5.2, 1.3)) * 0.2;
  return v;
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  GUI parameter accessors
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn ap_density() -> f32       { return clamp(#gui_param "density".x, 0.0, 20.0); }
fn ap_lifetime() -> f32      { return clamp(#gui_param "lifetime".x, 0.0, 20.0); }
fn ap_lt_rand() -> f32       { return clamp(#gui_param "lifetime_randomizer".x, 0.0, 1.0); }
fn ap_size() -> f32          { return clamp(#gui_param "particle_size".x, 0.0, 4.0); }
fn ap_weight() -> f32        { return clamp(#gui_param "weight".x, 0.0, 4.0); }
fn ap_softness() -> f32      { return clamp(#gui_param "softness".x, 0.0, 2.0); }
fn ap_transparency() -> f32  { return clamp(#gui_param "transparency".x, 0.0, 1.0); }
fn ap_depth_spread() -> f32  { return clamp(#gui_param "depth_spread".x, 0.0, 3.0); }
fn ap_glow() -> f32          { return clamp(#gui_param "glow_amount".x, 0.0, 2.0); }
fn ap_tint() -> vec3<f32>    { return #gui_param "tint".xyz; }
fn ap_turbulence() -> f32    { return clamp(#gui_param "turbulence".x, 0.0, 3.0); }
fn ap_wind_strength() -> f32 { return clamp(#gui_param "wind_strength".x, 0.0, 3.0); }
fn ap_wind_dir() -> f32      { return clamp(#gui_param "wind_direction".x, 0.0, 360.0); }

fn ap_swirl() -> f32 {
  return clamp(#gui_param "swirl".x, 0.0, 3.0);
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Layer configuration  (values from reference c3c11bb)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct LayerCfg {
  speed_mult: f32,
  size_mult: f32,
  alpha_mult: f32,
  softness_bias: f32,
  drift_mult: f32,
}

fn ap_layer_cfg(layer: u32) -> LayerCfg {
  let ds = ap_depth_spread();
  if (layer == 0u) {
    // Far – small, slow, faint, extra-soft
    return LayerCfg(0.62, 0.62, 0.18, 0.12, 0.75);
  }
  if (layer == 1u) {
    // Mid – reference baseline
    return LayerCfg(1.0, 1.18, 0.34, 0.0, 1.0);
  }
  // Near – large, fast, solid
  return LayerCfg(
    1.18 + ds * 0.18,
    2.2  + ds * 0.45,
    0.30,
    -0.03,
    1.18,
  );
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Derived properties  (all respond live to parameter changes)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn ap_active_count(cap: u32) -> u32 {
  let d = ap_density();
  if (d <= 0.0001) { return 0u; }
  return u32(clamp(ceil(pow(d / 20.0, 0.6) * f32(cap)), 1.0, f32(cap)));
}

fn ap_fall_speed(seed: vec4<f32>, layer: u32) -> f32 {
  let lcfg = ap_layer_cfg(layer);
  let w = ap_weight();
  // Per-particle speed variation via seed.z  (range: 0.055 .. 0.100)
  let base = 0.055 + seed.z * 0.045;
  // Weight→gravity curve:  w=0 → near-weightless (0.02),
  // w≥0.3 → blends smoothly into original formula mix(0.75, 1.2, w).
  let gravity = mix(0.02, mix(0.75, 1.2, w), smoothstep(0.0, 0.3, w));
  return base * gravity * lcfg.speed_mult;
}

fn ap_rest_duration(seed: vec4<f32>) -> f32 {
  let lt = ap_lifetime();
  let lr = ap_lt_rand();
  let scale = mix(max(1.0 - lr, 0.05), 1.0 + lr, seed.x);
  return max(lt * scale, 0.0);
}

fn ap_seed(idx: u32, gen: f32) -> vec4<f32> {
  let b = vec2<f32>(f32(idx) + gen * 17.0, gen * 0.37 + f32(idx) * 0.11);
  return vec4<f32>(ap_hash22(b + vec2<f32>(1.7, 9.2)), ap_hash22(b + vec2<f32>(17.3, 4.1)));
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Turbulence Force Fields — DVD-bounce wind vortices
//
//  1-3 invisible force fields float across the screen in
//  triangle-wave (DVD-logo) patterns. Particles within their
//  influence radius get a tangential (whirlwind) displacement.
//  Number of fields: turb>0→1, turb>1→2, turb>2→3.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn ap_bounce(t: f32, speed: f32, phase: f32) -> f32 {
  return abs(fract(t * speed + phase) * 2.0 - 1.0);
}

fn ap_field_center(idx: u32, time: f32) -> vec2<f32> {
  // Field drift speed influenced by weight (heavy atmosphere → slower fields)
  let w_scale = mix(1.4, 0.6, smoothstep(0.0, 2.0, ap_weight()));
  let t = time * w_scale;

  // Base DVD-bounce with weight-scaled speed
  var pos: vec2<f32>;
  if (idx == 0u) {
    pos = vec2<f32>(ap_bounce(t, 0.055, 0.10), ap_bounce(t, 0.038, 0.30));
  } else if (idx == 1u) {
    pos = vec2<f32>(ap_bounce(t, 0.067, 0.65), ap_bounce(t, 0.044, 0.45));
  } else {
    pos = vec2<f32>(ap_bounce(t, 0.041, 0.35), ap_bounce(t, 0.059, 0.80));
  }

  // Swirl enhances path wobble (more swirl → more organic path deviation)
  let wobble_amp = 0.04 + ap_swirl() * 0.025;
  pos.x += (ap_value_noise(vec2<f32>(t * 0.08, f32(idx) * 7.0)) - 0.5) * wobble_amp;
  pos.y += (ap_value_noise(vec2<f32>(t * 0.06, f32(idx) * 11.0 + 3.0)) - 0.5) * wobble_amp;

  // Wind pushes field centers in wind direction
  let wa = radians(ap_wind_dir());
  let ws = ap_wind_strength();
  pos.x += sin(wa) * ws * 0.04;
  pos.y += -cos(wa) * ws * 0.04;

  return clamp(pos, vec2<f32>(0.05), vec2<f32>(0.95));
}

fn ap_field_count() -> u32 {
  let t = ap_turbulence();
  if (t <= 0.001) { return 0u; }
  return u32(clamp(ceil(t), 1.0, 3.0));
}

fn ap_turb_force(
  px: f32, py: f32, seed: vec4<f32>, global_time: f32
) -> vec2<f32> {
  let count = ap_field_count();
  if (count == 0u) { return vec2<f32>(0.0, 0.0); }

  let turb = ap_turbulence();
  let influence = 0.144 + turb * 0.06;
  let strength = turb * 0.008;
  let lightness = mix(2.0, 1.0, smoothstep(0.0, 0.5, ap_weight()));

  // Wind direction (shared by all fields)
  let wa = radians(ap_wind_dir());
  let wind_vec = vec2<f32>(sin(wa), -cos(wa));
  let ws = max(ap_wind_strength(), 0.1);

  // Per-particle random direction (30% weight)
  let rnd = vec2<f32>(
    (ap_value_noise(vec2<f32>(px * 7.0 + seed.x * 11.0, py * 7.0 + seed.y * 11.0)) - 0.5),
    (ap_value_noise(vec2<f32>(px * 9.0 + seed.z * 13.0, py * 5.0 + seed.w * 9.0)) - 0.5),
  );

  // Per-particle magnitude randomizer (some react strongly, some weakly)
  let mag_rng = 0.3 + seed.z * 1.4;   // range [0.3 .. 1.7]

  var force = vec2<f32>(0.0, 0.0);

  // --- Field 0 ---
  {
    let c = ap_field_center(0u, global_time);
    let r = vec2<f32>(px - c.x, py - c.y);
    let d = length(r);
    let falloff = smoothstep(influence, influence * 0.08, d);
    if (falloff > 0.001) {
      let tang = vec2<f32>(-r.y, r.x) / max(d, 0.001);
      let combined = tang * 0.55 + wind_vec * 0.15 * ws + rnd * 0.30;
      force += combined * falloff * strength * mag_rng;
    }
  }

  // --- Field 1 ---
  if (count >= 2u) {
    let c = ap_field_center(1u, global_time);
    let r = vec2<f32>(px - c.x, py - c.y);
    let d = length(r);
    let falloff = smoothstep(influence, influence * 0.08, d);
    if (falloff > 0.001) {
      let tang = vec2<f32>(-r.y, r.x) / max(d, 0.001);
      let combined = tang * 0.55 + wind_vec * 0.15 * ws + rnd * 0.30;
      force += combined * falloff * strength * mag_rng;
    }
  }

  // --- Field 2 ---
  if (count >= 3u) {
    let c = ap_field_center(2u, global_time);
    let r = vec2<f32>(px - c.x, py - c.y);
    let d = length(r);
    let falloff = smoothstep(influence, influence * 0.08, d);
    if (falloff > 0.001) {
      let tang = vec2<f32>(-r.y, r.x) / max(d, 0.001);
      let combined = tang * 0.55 + wind_vec * 0.15 * ws + rnd * 0.30;
      force += combined * falloff * strength * mag_rng;
    }
  }

  return force * lightness;
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Horizontal motion  (swirl-only, smooth fbm drift)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn ap_horizontal(
  fall_time: f32,
  seed: vec4<f32>,
  layer: u32,
  initial_x: f32,
  y_pos: f32,
) -> f32 {
  let lcfg = ap_layer_cfg(layer);
  let ls = f32(layer) * 17.0 + 1.0;
  let swirl = ap_swirl();
  let ws = ap_wind_strength();
  let phase = seed.w * TAU;

  // ── SWIRL COMPONENTS (100% fbm-based = guaranteed smooth, no jitter) ─

  // 1. Primary drift: slow, gentle lateral wandering
  let drift = (ap_fbm(vec2<f32>(
    fall_time * (0.14 + seed.z * 0.08) + seed.w * 8.0 + seed.y * 23.7,
    seed.x * 11.0 + seed.z * 19.3 + ls * 0.7,
  )) - 0.5) * 0.012;

  // 2. Path noise: medium-scale fbm meandering per particle
  let path = (ap_fbm(vec2<f32>(
    fall_time * (0.27 + seed.x * 0.15) + seed.y * 5.1 + seed.w * 31.1,
    seed.x * 9.7 + seed.y * 14.9 + ls * 0.37,
  )) - 0.5) * 0.014;

  // 3. Atmospheric shear: height-dependent lateral push
  let shear = (ap_fbm(vec2<f32>(
    y_pos * 1.6 + ls + seed.w * 7.3,
    seed.x * 5.0 + seed.z * 11.7 + ls * 0.37,
  )) - 0.5) * 0.010;

  // 4. Meander: very slow, large-scale directional wandering
  let meander = (ap_fbm(vec2<f32>(
    fall_time * (0.08 + seed.x * 0.05) + seed.w * 8.3 + seed.y * 17.9,
    seed.z * 6.1 + seed.x * 22.3 + ls * 1.9,
  )) - 0.5) * 0.014;

  // Weight coupling: lighter particles drift more, heavier resist
  let w_swirl_damp = mix(1.8, 0.5, smoothstep(0.0, 2.0, ap_weight()));
  let swirl_rng = 0.4 + seed.w * 1.2;

  let gentle = (drift + path + shear + meander) * swirl * lcfg.drift_mult * w_swirl_damp * swirl_rng;

  // 5. Wind – directional push that grows with fall time
  let wa = radians(ap_wind_dir());
  let wind_x = sin(wa);
  let wn = 0.85 + ap_hash21(vec2<f32>(initial_x * 97.0, ls * 13.0)) * 0.3;
  let gust = 0.75 + ap_fbm(vec2<f32>(
    fall_time * 0.4 + seed.x * 4.1,
    ls * 0.23 + seed.y * 3.7,
  )) * 0.5;
  let life_curve = smoothstep(0.0, 1.0, min(fall_time * 0.15, 1.0));
  let wind = life_curve * ws * wind_x * wn * gust * 0.18;

  let lightness = mix(3.0, 1.0, smoothstep(0.0, 0.5, ap_weight()));

  return (gentle + wind) * lightness;
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Soft disc shape
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

fn ap_soft_disc(uv: vec2<f32>, softness: f32) -> f32 {
  let c = uv * 2.0 - 1.0;
  let d = length(c);
  let edge = max(1.0 - softness * 0.7, 0.2);
  return clamp(
    (1.0 - smoothstep(edge, 1.0, d)) + exp(-d * d / 0.42) * 0.36,
    0.0, 1.0,
  );
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ff_init — Hybrid staggered initialization
//
//  Two groups ensure BOTH empty-frame-1 AND continuous flow:
//    FALL group  (~fall_dur/total_cycle of particles):
//      Placed ABOVE screen at staggered heights → cascade in from top
//      over fall_dur seconds → frame 1 is empty, gradual buildup.
//    REST group  (~rest_dur/total_cycle of particles):
//      Start with staggered rest timers → emerge at different times
//      throughout the song → continuous replenishment, no gaps.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@compute @workgroup_size(64)
fn ff_init(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  let cap = u32(params.runtime_meta.x);
  if (idx >= cap) { return; }

  let seed = ap_seed(idx, params.runtime_meta.z);

  // --- Layer assignment: 40% far, 40% mid, 20% near ---
  var layer = 1u;
  if (seed.x < 0.40) { layer = 0u; }
  else if (seed.x >= 0.80) { layer = 2u; }

  // --- Uniform random X position ---
  let initial_x = fract(seed.x * 7.31 + seed.z * 3.17);

  // --- Compute this particle's full lifecycle timing ---
  let speed = ap_fall_speed(seed, layer);
  let top_margin = 0.05 + seed.y * 0.10;
  let bottom_max = 1.05 + seed.x * 0.08;
  let travel = bottom_max + top_margin;
  let fall_dur = travel / max(speed, 0.0001);
  let rest_dur = ap_rest_duration(seed);
  let total_cycle = fall_dur + max(rest_dur, 0.01);
  let fall_fraction = fall_dur / total_cycle;

  // --- Assign each particle to FALL or REST group via seed.y ---
  let phase = seed.y;   // uniform [0, 1]

  var y_pos: f32;
  var fall_time: f32;
  var rest_timer: f32;

  if (phase < fall_fraction) {
    // FALL GROUP: place ABOVE screen, staggered vertically.
    // phase 0 → just above top edge (enters first),
    // phase → fall_fraction → far above (enters last, after ~fall_dur).
    let normalized = phase / max(fall_fraction, 0.001);   // [0..1]
    let depth_above = normalized * travel;                // 0 .. travel
    y_pos = -(depth_above + top_margin);
    fall_time = 0.0;
    rest_timer = 0.0;
  } else {
    // REST GROUP: start with staggered rest timers.
    // These particles will respawn at the top at different times
    // throughout the song, creating continuous replenishment.
    let normalized = (phase - fall_fraction) / max(1.0 - fall_fraction, 0.001);
    let remaining_rest = rest_dur * (1.0 - normalized);
    y_pos = -top_margin;
    fall_time = 0.0;
    rest_timer = -remaining_rest;
  }

  let is_on = select(0.0, 1.0, idx < ap_active_count(cap));

  state_out[idx] = ParticleState(
    vec4<f32>(y_pos, fall_time, rest_timer, 0.0),
    vec4<f32>(f32(layer), initial_x, initial_x, 0.0),
    vec4<f32>(is_on, 0.0, 0.0, 0.0),
    seed,
  );
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ff_update — Per-frame particle simulation
//
//  Simple state machine:
//    rest_timer < 0  →  resting (counting up toward 0, then respawn)
//    rest_timer >= 0 →  falling (move y down, compute drift)
//    y > bottom      →  enter rest or immediate respawn
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@compute @workgroup_size(64)
fn ff_update(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  let cap = u32(params.runtime_meta.x);
  if (idx >= cap) { return; }

  var p = state_in[idx];

  let dt = params.runtime_meta.w;

  // --- Global time accumulator (stored in particle 0, read by all) ---
  let global_time = state_in[0].style.z + dt;

  // --- Density-based activation ---
  let is_active = idx < ap_active_count(cap);
  if (!is_active) {
    p.style.x = 0.0;
    p.style.y = 0.0;
    if (idx == 0u) { p.style.z = global_time; }
    state_out[idx] = p;
    return;
  }

  // --- Reactivate dormant particles (density increased) ---
  if (p.style.x <= 0.5) {
    let seed = ap_seed(idx, params.runtime_meta.z);
    var layer = 1u;
    if (seed.x < 0.40) { layer = 0u; }
    else if (seed.x >= 0.80) { layer = 2u; }
    let ix = fract(seed.x * 7.31 + seed.z * 3.17);
    p = ParticleState(
      vec4<f32>(-0.05, 0.0, 0.0, 0.0),
      vec4<f32>(f32(layer), ix, ix, 0.0),
      vec4<f32>(1.0, 0.0, 0.0, 0.0),
      seed,
    );
  }

  let seed = p.seed_data;
  let layer = u32(clamp(round(p.velocity_life.x), 0.0, 2.0));
  let initial_x = p.velocity_life.y;

  var y_pos      = p.pos_age.x;
  var fall_time  = p.pos_age.y;
  var rest_timer = p.pos_age.z;
  var cycle      = p.pos_age.w;

  let speed = ap_fall_speed(seed, layer);
  let top_margin = 0.05 + seed.y * 0.10;
  let bottom_max = 1.05 + seed.x * 0.08;

  var visible = false;

  if (rest_timer < 0.0) {
    rest_timer += dt;
    if (rest_timer >= 0.0) {
      y_pos = -top_margin;
      fall_time = 0.0;
      rest_timer = 0.0;
      cycle += 1.0;
    }
  } else {
    y_pos += speed * dt;
    fall_time += dt;

    if (y_pos >= bottom_max) {
      let rest = ap_rest_duration(seed);
      if (rest > 0.01) {
        rest_timer = -rest;
      } else {
        y_pos = -top_margin;
        fall_time = 0.0;
        cycle += 1.0;
        visible = true;
      }
    } else {
      visible = true;
    }
  }

  // --- Swirl offset (EMA smoothed, symmetric rate) ---
  let swirl_h = ap_horizontal(fall_time, seed, layer, initial_x, y_pos);
  let prev_swirl_h = p.velocity_life.w;
  let swirl_alpha = 1.0 - exp(-dt * 3.0);
  let smoothed_swirl = mix(prev_swirl_h, swirl_h, swirl_alpha);

  // --- Turbulence force field (asymmetric: fast attack, slow decay) ---
  let prev_dx = p.velocity_life.z;
  let turb_f = ap_turb_force(prev_dx, y_pos, seed, global_time);
  let turb_target = turb_f.x;
  let prev_turb_h = p.style.w;
  // Detect if vortex is actively pushing (attack) or particle is trailing (decay)
  let turb_active = smoothstep(0.0, 0.001, abs(turb_target));
  let turb_rate = mix(0.5, 4.0, turb_active);   // responsive attack, long trailing decay
  let turb_alpha = 1.0 - exp(-dt * turb_rate);
  let smoothed_turb = mix(prev_turb_h, turb_target, turb_alpha);

  // --- Post-move path smoother (final safety net for ALL jumps) ---
  let raw_x = fract(initial_x + smoothed_swirl + smoothed_turb + 1.0);
  let prev_x = p.velocity_life.z;
  var dx_diff = raw_x - prev_x;
  if (dx_diff > 0.5) { dx_diff -= 1.0; }
  if (dx_diff < -0.5) { dx_diff += 1.0; }
  let post_alpha = 1.0 - exp(-dt * 12.0);  // nearly passthrough — only catches extreme jumps
  let display_x = fract(prev_x + dx_diff * post_alpha + 1.0);

  // --- Write state ---
  p.pos_age       = vec4<f32>(y_pos, fall_time, rest_timer, cycle);
  p.velocity_life = vec4<f32>(f32(layer), initial_x, display_x, smoothed_swirl);
  p.style.x       = 1.0;
  p.style.y       = select(0.0, 1.0, visible);
  if (idx == 0u) { p.style.z = global_time; }
  p.style.w       = smoothed_turb;

  state_out[idx] = p;
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ff_vs — Billboard vertex shader
//
//  Places a screen-aligned quad at each particle position.
//  All visual properties derived LIVE from (seed + current params).
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@vertex
fn ff_vs(
  @builtin(vertex_index) vi: u32,
  @builtin(instance_index) ii: u32,
) -> RenderOut {
  let p = state_in[ii];
  let aspect = params.texel_size.y / max(params.texel_size.x, 0.000001);

  var positions = array<vec2<f32>, 6>(
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0),  vec2<f32>(-1.0, 1.0),
  );
  var uvs = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 1.0), vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 0.0),
  );

  var out: RenderOut;

  // Cull invisible / inactive particles → degenerate quad off-screen
  if (p.style.y <= 0.0001) {
    out.position = vec4<f32>(2.0, 2.0, 0.0, 1.0);
    out.local_uv = uvs[vi];
    out.alpha_scale = 0.0;
    out.tint = vec3<f32>(0.0);
    out.softness_bias = 0.0;
    return out;
  }

  let seed = p.seed_data;
  let layer = u32(clamp(round(p.velocity_life.x), 0.0, 2.0));
  let lcfg = ap_layer_cfg(layer);
  let fall_time = p.pos_age.y;

  // --- Position from update pass ---
  var dx = p.velocity_life.z;   // display X [0..1]
  var dy = p.pos_age.x;         // Y position

  // --- Vertical swirl drift (fbm-based) ---
  let ls_v = f32(layer) * 17.0 + 1.0;
  let w_damp = mix(1.8, 0.5, smoothstep(0.0, 2.0, ap_weight()));
  let v_swirl = (ap_fbm(vec2<f32>(
    fall_time * (0.10 + seed.y * 0.06) + seed.x * 15.3 + seed.z * 27.1,
    seed.w * 8.7 + seed.y * 19.4 + ls_v * 1.3,
  )) - 0.5) * 0.010 * ap_swirl() * w_damp * (0.4 + seed.z * 1.2);

  // --- Turbulence force field (vertical component) ---
  let global_time = state_in[0].style.z;
  let turb_v = ap_turb_force(dx, dy, seed, global_time);
  dy += v_swirl + turb_v.y * 0.25;  // vertical turb subtle, horizontal dominates

  // --- Particle radius: seed × param × layer ---
  let radius = (0.006 + seed.y * 0.009) * ap_size() * lcfg.size_mult;

  // --- Clip-space quad ---
  let local = positions[vi];
  let cx = dx * 2.0 - 1.0 + local.x * radius * 2.0 / aspect;
  let cy = 1.0 - dy * 2.0 + local.y * radius * 2.0;

  // --- Alpha (live from transparency + layer + seed) ---
  let alpha_var = 0.82 + seed.x * 0.34;
  let alpha = mix(3.2, 0.35, ap_transparency()) * lcfg.alpha_mult * alpha_var;

  // --- Edge fade: soften particles at horizontal screen edges ---
  let edge_x = min(dx, 1.0 - dx) * 2.0;
  let edge_fade = smoothstep(0.0, 0.06, edge_x);

  // --- Tint: cool white base, mixed with user tint, depth-shaded ---
  let cool = vec3<f32>(0.94, 0.97, 1.0);
  let depth_shade = mix(1.08, 0.86, clamp((lcfg.size_mult - 0.6) / 2.0, 0.0, 1.0));

  out.position = vec4<f32>(cx, cy, 0.0, 1.0);
  out.local_uv = uvs[vi];
  out.alpha_scale = alpha * edge_fade;
  out.tint = mix(cool, ap_tint(), 0.45) * mix(0.92, 1.05, seed.y) * depth_shade;
  out.softness_bias = lcfg.softness_bias;
  return out;
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ff_fs — Soft-disc fragment shader
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@fragment
fn ff_fs(in: RenderOut) -> @location(0) vec4<f32> {
  let softness = ap_softness() + in.softness_bias;
  let shape = ap_soft_disc(in.local_uv, softness);
  let glow = vec3<f32>(0.2, 0.26, 0.34) * ap_glow();
  let alpha = min(shape * in.alpha_scale, 1.0);
  let color = in.tint + glow;
  // Non-premultiplied output: engine blends via (SrcAlpha, 1-SrcAlpha)
  return vec4<f32>(color, alpha);
}
