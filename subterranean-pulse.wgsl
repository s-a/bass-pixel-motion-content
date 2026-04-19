#import <engine::bpm_kernel_bindings>

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 2D Hash function
fn hash21(p: vec2<f32>) -> f32 {
    // Added offset to prevent 0,0 from returning exactly 0.0 (which flattened the start of the cavern)
    var p3  = fract(vec3(p.xyx) * .1031 + vec3<f32>(0.71, 0.31, 0.82));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Value Noise 2D
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f*f*(3.0-2.0*f);
    return mix(mix(hash21(i + vec2(0.0,0.0)), hash21(i + vec2(1.0,0.0)), u.x),
               mix(hash21(i + vec2(0.0,1.0)), hash21(i + vec2(1.0,1.0)), u.x), u.y);
}

// Voronoi / Cellular noise approximation for cracks
fn voronoi(x: vec2<f32>) -> vec3<f32> {
    let n = floor(x);
    let f = fract(x);
    
    var m = vec3<f32>(8.0);
    for(var j = -1; j <= 1; j = j + 1) {
        for(var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash21(n + g);
            // Pseudo-random offset
            let offset = vec2<f32>(fract(o * 34.0), fract(o * 123.0));
            let d = length(g - f + offset);
            
            if(d < m.x) {
                m.z = m.y;
                m.y = m.x;
                m.x = d;
            } else if(d < m.y) {
                m.z = m.y;
                m.y = d;
            } else if(d < m.z) {
                m.z = d;
            }
        }
    }
    return m;
}

// Fractional Brownian Motion (FBM)
fn fbm(p: vec2<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for(var i = 0u; i < 4u; i = i + 1u) {
        val += amp * noise(pos);
        pos *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// Map the distance to the cavern (floor and ceiling combined)
fn map(pos: vec3<f32>, roughness: f32, nscale: f32, pattern: i32, terrainHeight: f32) -> f32 {
    // Add a huge rigid offset to physically disconnect the procedural geometry from the origin (0, 0, 0).
    // This strictly prevents sin(0)=0 flatness down the camera's center tunnel!
    let p = pos + vec3<f32>(1234.5, 0.0, 6789.1);
    let height = 0.8; // Lowered height for more claustrophobic cavern
    
    var dispFloor = 0.0;
    var ridgesFloor = 0.0;
    var dispCeil = 0.0;
    
    // Solid rock terrain without time displacement so it doesn't judder
    if (pattern == 1) {
        // Digital Grid Core
        let grid = abs(fract(p.xz * nscale * 0.5) - 0.5);
        dispFloor = (0.5 - min(grid.x, grid.y)) * 0.8;
        dispCeil = (0.5 - min(grid.x, grid.y)) * 0.6;
    } else if (pattern == 2) {
        // Liquid Geode
        dispFloor = sin(p.x * nscale) * sin(p.z * nscale) * 0.8;
        ridgesFloor = fbm(p.xz * nscale * 2.0) * 0.3;
        dispCeil = cos(p.x * nscale) * cos(p.z * nscale) * 0.5;
    } else {
        // Pattern 0: Voronoi Faultlines
        dispFloor = fbm(p.xz * nscale * 0.7) * 0.7;
        ridgesFloor = (0.5 - abs(fbm(p.xz * nscale * 1.5) - 0.5)) * 0.5;
        dispCeil = fbm(p.xz * 1.5 * nscale) * 0.5;
    }
    
    // Scale vertical displacement strictly and exclusively by terrainHeight
    // Roughness is baked into the base constant (1.5) to prevent any regression
    dispFloor *= 1.5 * terrainHeight;
    ridgesFloor *= 1.5 * terrainHeight;
    dispCeil *= 1.5 * terrainHeight;

    // Distances
    let dFloor = (p.y + height) - dispFloor + ridgesFloor;
    let dCeil = (height - p.y) - dispCeil;
    
    return min(dFloor, dCeil);
}

// Normal Calculation via central differences
fn calcNormal(p: vec3<f32>, roughness: f32, nscale: f32, pattern: i32, terrainHeight: f32) -> vec3<f32> {
    let e = vec2<f32>(0.005, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, roughness, nscale, pattern, terrainHeight) - map(p - e.xyy, roughness, nscale, pattern, terrainHeight),
        map(p + e.yxy, roughness, nscale, pattern, terrainHeight) - map(p - e.yxy, roughness, nscale, pattern, terrainHeight),
        map(p + e.yyx, roughness, nscale, pattern, terrainHeight) - map(p - e.yyx, roughness, nscale, pattern, terrainHeight)
    ));
}

// Get rich emissive cracks based on Voronoi edges - using fine blinking lines
fn getEmission(p: vec3<f32>, animTime: f32, nscale: f32, crack_width: f32, pattern: i32) -> f32 {
    let w = max(crack_width, 0.001);
    
    if(pattern == 1) { // Cyber Circuitry
        // Sharp, thin matrix-style lines on exact grid boundaries
        let grid = abs(fract(p.xz * nscale * 0.5) - 0.5);
        let dist = min(grid.x, grid.y);
        let fine_line = exp(-dist * (20.0 / w));
        let pulse = pow(sin(p.z * 10.0 - animTime * 8.0) * 0.5 + 0.5, 3.0);
        return fine_line * (0.4 + 0.6 * pulse);
        
    } else if (pattern == 2) { // Bioluminescent Veins
        // Contour map style fine glowing strata
        let val = sin(p.x * nscale * 1.5) * sin(p.z * nscale * 1.5);
        let fine_line = exp(-abs(val) * (15.0 / w));
        let pulse = pow(sin(p.x * 3.0 + p.z * 5.0 - animTime * 6.0) * 0.5 + 0.5, 4.0);
        return fine_line * (0.3 + 0.7 * pulse);
        
    } else if (pattern == 3) { // Energy Seams
        let cx = p.x * nscale;
        let cy = p.z * nscale * 1.1547;
        let bx = abs(fract(cx) - 0.5);
        let by = abs(fract(cy) - 0.5);
        let bz = abs(fract(cx * 0.5 + cy * 0.5) - 0.5);
        let hexdist = min(min(bx, by), bz);
        let fine_line = exp(-hexdist * (25.0 / w));
        let mask = fbm(p.xz * 10.0) * 0.5 + 0.5;
        let pulse = pow(sin(p.z * 8.0 - animTime * 12.0) * 0.5 + 0.5, 2.0);
        return fine_line * mask * (0.4 + 0.6 * pulse);
        
    } else {
        // Pattern 0: Fractured Energy
        let v_dist = voronoi(p.xz * nscale);
        let fine_line = exp(-(v_dist.y - v_dist.x) * (12.0 / w));
        let mask = fbm(p.xz * 15.0) * 0.5 + 0.5;
        let pulse = pow(sin(v_dist.x * 20.0 - animTime * 10.0) * 0.5 + 0.5, 3.0);
        return fine_line * mask * (0.5 + 0.5 * pulse);
    }
}

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOut {
    var p = array<vec2<f32>, 3>(
        vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0)
    );
    var out: VertexOut;
    out.clip_position = vec4<f32>(p[vi], 0.0, 1.0);
    out.uv = p[vi] * 0.5 + 0.5;
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    // Boilerplate UV Setup & Aspect Ratio
    let uv = in.uv * 2.0 - 1.0;
    var uv_aspect = uv;
    uv_aspect.x *= scene.resolution.x / scene.resolution.y;
    
    // Virtual Engine Bindings mapped directly to simple names
    let colBg = #color "bg_color";
    let colAmbient = #color "ambient_color";
    let colAccent = #color "accent_color";
    let colPulse = #color "pulse_color";
    
    let aKick = #audio "audio.stem.kicks.peak";
    let valKick = aKick.clamped_safe;
    let aRms = #audio "audio.rms";
    let valRms = aRms.clamped_safe;
    
    let localTime = scene.time;
    let songProgress = scene.timeline.z;
    
    let pCamSpeed = (#gui_param "camera_speed").x;
    let pRough = (#gui_param "geo_roughness").x;
    let pScale = (#gui_param "geo_scale").x;
    let pTerrainHeight = (#gui_param "geo_height").x;
    let pWidth = (#gui_param "glow_width").x;
    let pThresh = (#gui_param "emissive_threshold").x;
    let pRoll = (#gui_param "camera_roll").x;
    let pDrone = (#gui_param "drone_wobble").x;
    let pTerrainPat = i32((#gui_param "geo_pattern").x + 0.1);
    let pGlowPat = i32((#gui_param "emissive_pattern").x + 0.1);
    let pSimSpeed = (#gui_param "pulse_speed").x;

    // Dynamic Speed & Motion
    let moveTime = localTime * pCamSpeed * 0.5;
    
    // Camera System (Forward Flythrough)
    // Offset by 5000 units to completely avoid the z=0 graphical singularity 
    // where sin(p.z) = 0 caused the world to flatten when speed was exactly 0.0
    let camZ = moveTime * 2.0 + 5123.4;
    
    // Natural drone flight uses compounded sines for pseudo-random smooth drift
    let t = localTime;
    let ramp = smoothstep(0.0, 4.0, t); // smoothly introduce the drone wobble over the first 4 seconds
    
    let dx = sin(t * 0.3) + 0.5 * sin(t * 0.77 + 2.0) + 0.3 * sin(t * 1.2 + 4.0);
    let dy = sin(t * 0.4 + 1.0) + 0.4 * sin(t * 1.1 + 3.0);
    
    var ro = vec3<f32>(
        dx * 0.35 * pDrone * ramp,
        dy * 0.25 * pDrone * ramp,
        camZ
    );
    
    // Target leads the way
    var camTarget = vec3<f32>(0.0, 0.0, camZ + 3.0);
    let lx = sin((t + 0.5) * 0.3) + 0.5 * sin((t + 0.5) * 0.77 + 2.0) + 0.3 * sin((t + 0.5) * 1.2 + 4.0);
    let ly = sin((t + 0.5) * 0.4 + 1.0) + 0.4 * sin((t + 0.5) * 1.1 + 3.0);
    
    camTarget.x = lx * 0.4 * pDrone * smoothstep(0.0, 4.0, t + 0.5);
    camTarget.y = ly * 0.3 * pDrone * smoothstep(0.0, 4.0, t + 0.5);
    
    let cz = normalize(camTarget - ro);
    let cx = normalize(cross(cz, vec3<f32>(0.0, 1.0, 0.0)));
    let cy = normalize(cross(cx, cz));
    
    // Apply Roll
    let rollAngle = pRoll * 3.1415;
    let rM = rot(rollAngle);
    let cxR = rM[0].x * cx + rM[0].y * cy;
    let cyR = rM[1].x * cx + rM[1].y * cy;
    
    let rd = normalize(cxR * uv_aspect.x + cyR * uv_aspect.y + cz * 1.5);
    
    // Raymarching
    var dO = 0.0;
    var hit = false;
    var p = ro;
    
    for(var i = 0; i < 30; i = i + 1) {
        p = ro + rd * dO;
        let dS = map(p, pRough, pScale, pTerrainPat, pTerrainHeight);
        if(dS < 0.005) { hit = true; break; }
        if(dO > 40.0) { break; }
        dO += dS * 0.85; // Faster travel
    }
    
    var finalCol = colBg.rgb;
    
    if(hit) {
        let n = calcNormal(p, pRough, pScale, pTerrainPat, pTerrainHeight);
        // Cinematic split lighting
        let lDir1 = normalize(vec3<f32>(0.8, 0.5, 0.6));
        let lDir2 = normalize(vec3<f32>(-0.8, -0.2, 0.4));
        
        // Base rock rendering
        let dif1 = max(0.0, dot(n, lDir1));
        let dif2 = max(0.0, dot(n, lDir2));
        
        let rockBase = colAmbient.rgb * (0.2 + dif1 * 0.4 + dif2 * 0.2);
        
        // Emissive Cracks based on fine line pattern
        let animTime = localTime * pSimSpeed;
        let emIntensity = getEmission(p, animTime, pScale, pWidth, pGlowPat);
        
        // The threshold mask is now much sharper and isolates only high intensity areas
        let activeEm = smoothstep(1.0 - pThresh, 0.98, emIntensity);
        
        // Let the kick audio pump the emission layer's life
        let kickPump = smoothstep(0.4, 1.0, valKick) * 2.0;
        
        // Mix accent and core pulse
        let coreHeat = emIntensity + valKick * 0.4;
        let glowCol = mix(colAccent.rgb, colPulse.rgb, saturate(coreHeat));
        
        // Apply glow on top of rock base
        finalCol = mix(rockBase, glowCol * (2.0 + kickPump), activeEm);
        
        // Specular highlight for a slick, wet crystal look
        let refDir = reflect(rd, n);
        let spec = pow(max(dot(refDir, lDir1), 0.0), 32.0);
        finalCol += colPulse.rgb * spec * 0.15; 
    }
    
    // Volumetric Depth Fog
    let fogDensity = 0.12 - (valRms * 0.03); 
    let fogFactor = 1.0 - exp( -dO * dO * fogDensity * fogDensity );
    let fogColor = mix(colBg.rgb, colAccent.rgb * 0.1, valRms * 0.5);
    
    finalCol = mix(finalCol, fogColor, fogFactor);
    
    // Add simple ambient haze
    finalCol += colAccent.rgb * (1.0 - exp(-dO * 0.03)) * 0.05;
    
    // Cinematic Vignette
    let dist = length(uv);
    finalCol *= exp(-dist * 0.75);
    
    return encode_output_alpha(finalCol, colBg.a);
}
