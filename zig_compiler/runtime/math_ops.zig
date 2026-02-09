//
// math_ops.zig
// FasterBASIC Runtime — Math Operations
//
// Implements all mathematical functions for BASIC programs.
// Pure wrappers around libm with domain-error checking.
//

const std = @import("std");
const math = std.math;

// =========================================================================
// Extern declarations
// =========================================================================

extern fn basic_error_msg(msg: [*:0]const u8) void;

// C math library functions not directly in Zig std.math
extern fn fabs(x: f64) f64;
extern fn sqrt(x: f64) f64;
extern fn pow(base: f64, exp: f64) f64;
extern fn sin(x: f64) f64;
extern fn cos(x: f64) f64;
extern fn tan(x: f64) f64;
extern fn asin(x: f64) f64;
extern fn acos(x: f64) f64;
extern fn atan(x: f64) f64;
extern fn atan2(y: f64, x: f64) f64;
extern fn sinh(x: f64) f64;
extern fn cosh(x: f64) f64;
extern fn tanh(x: f64) f64;
extern fn asinh(x: f64) f64;
extern fn acosh(x: f64) f64;
extern fn atanh(x: f64) f64;
extern fn log(x: f64) f64;
extern fn exp(x: f64) f64;
extern fn exp2(x: f64) f64;
extern fn expm1(x: f64) f64;
extern fn log10(x: f64) f64;
extern fn log1p(x: f64) f64;
extern fn cbrt(x: f64) f64;
extern fn hypot(x: f64, y: f64) f64;
extern fn fmod(x: f64, y: f64) f64;
extern fn remainder(x: f64, y: f64) f64;
extern fn floor(x: f64) f64;
extern fn ceil(x: f64) f64;
extern fn trunc(x: f64) f64;
extern fn round(x: f64) f64;
extern fn copysign(x: f64, y: f64) f64;
extern fn erf(x: f64) f64;
extern fn erfc(x: f64) f64;
extern fn tgamma(x: f64) f64;
extern fn lgamma(x: f64) f64;
extern fn nextafter(x: f64, y: f64) f64;
extern fn fmax(x: f64, y: f64) f64;
extern fn fmin(x: f64, y: f64) f64;
extern fn fma(x: f64, y: f64, z: f64) f64;

// C stdlib for RNG
extern fn srand(seed: c_uint) void;
extern fn rand() c_int;
extern fn time(t: ?*anyopaque) c_long;

const RAND_MAX: c_int = 0x7fffffff;

const M_PI: f64 = 3.14159265358979323846;
const M_SQRT2: f64 = 1.41421356237309504880;

// =========================================================================
// Absolute Value
// =========================================================================

export fn basic_abs_int(x: i32) callconv(.c) i32 {
    return if (x < 0) -x else x;
}

export fn basic_abs_double(x: f64) callconv(.c) f64 {
    return fabs(x);
}

// =========================================================================
// Square Root
// =========================================================================

export fn basic_sqrt(x: f64) callconv(.c) f64 {
    if (x < 0.0) {
        basic_error_msg("Square root of negative number");
        return 0.0;
    }
    return sqrt(x);
}

// =========================================================================
// Power
// =========================================================================

export fn basic_pow(base_val: f64, exponent: f64) callconv(.c) f64 {
    if (base_val == 0.0 and exponent < 0.0) {
        basic_error_msg("Division by zero in power operation");
        return 0.0;
    }
    return pow(base_val, exponent);
}

// =========================================================================
// Extended Exponentials and Logarithms
// =========================================================================

export fn basic_exp2(x: f64) callconv(.c) f64 {
    return exp2(x);
}

export fn basic_expm1(x: f64) callconv(.c) f64 {
    return expm1(x);
}

export fn basic_log10(x: f64) callconv(.c) f64 {
    if (x <= 0.0) {
        basic_error_msg("Logarithm base 10 of non-positive number");
        return 0.0;
    }
    return log10(x);
}

export fn basic_log1p(x: f64) callconv(.c) f64 {
    if (x <= -1.0) {
        basic_error_msg("Logarithm of 1 + x with x <= -1");
        return 0.0;
    }
    return log1p(x);
}

// =========================================================================
// Trigonometric Functions
// =========================================================================

export fn basic_sin(x: f64) callconv(.c) f64 {
    return sin(x);
}

export fn basic_cos(x: f64) callconv(.c) f64 {
    return cos(x);
}

export fn basic_tan(x: f64) callconv(.c) f64 {
    return tan(x);
}

export fn basic_asin(x: f64) callconv(.c) f64 {
    if (x < -1.0 or x > 1.0) {
        basic_error_msg("ASIN domain error");
        return 0.0;
    }
    return asin(x);
}

export fn basic_acos(x: f64) callconv(.c) f64 {
    if (x < -1.0 or x > 1.0) {
        basic_error_msg("ACOS domain error");
        return 0.0;
    }
    return acos(x);
}

export fn basic_atan(x: f64) callconv(.c) f64 {
    return atan(x);
}

export fn basic_atan2(y: f64, x: f64) callconv(.c) f64 {
    return atan2(y, x);
}

// Hyperbolic functions
export fn basic_sinh(x: f64) callconv(.c) f64 {
    return sinh(x);
}

export fn basic_cosh(x: f64) callconv(.c) f64 {
    return cosh(x);
}

export fn basic_tanh(x: f64) callconv(.c) f64 {
    return tanh(x);
}

export fn basic_asinh(x: f64) callconv(.c) f64 {
    return asinh(x);
}

export fn basic_acosh(x: f64) callconv(.c) f64 {
    if (x < 1.0) {
        basic_error_msg("ACOSH domain error");
        return 0.0;
    }
    return acosh(x);
}

export fn basic_atanh(x: f64) callconv(.c) f64 {
    if (x <= -1.0 or x >= 1.0) {
        basic_error_msg("ATANH domain error");
        return 0.0;
    }
    return atanh(x);
}

// =========================================================================
// Logarithm and Exponential
// =========================================================================

export fn basic_log(x: f64) callconv(.c) f64 {
    if (x <= 0.0) {
        basic_error_msg("Logarithm of non-positive number");
        return 0.0;
    }
    return log(x);
}

export fn basic_exp(x: f64) callconv(.c) f64 {
    return exp(x);
}

// =========================================================================
// Power Helpers and Roots
// =========================================================================

export fn basic_cbrt(x: f64) callconv(.c) f64 {
    return cbrt(x);
}

export fn basic_hypot(x: f64, y: f64) callconv(.c) f64 {
    return hypot(x, y);
}

export fn basic_fmod(x: f64, y: f64) callconv(.c) f64 {
    if (y == 0.0) {
        basic_error_msg("FMOD division by zero");
        return 0.0;
    }
    return fmod(x, y);
}

export fn basic_remainder(x: f64, y: f64) callconv(.c) f64 {
    if (y == 0.0) {
        basic_error_msg("REMAINDER division by zero");
        return 0.0;
    }
    return remainder(x, y);
}

export fn basic_floor(x: f64) callconv(.c) f64 {
    return floor(x);
}

export fn basic_ceil(x: f64) callconv(.c) f64 {
    return ceil(x);
}

export fn basic_trunc(x: f64) callconv(.c) f64 {
    return trunc(x);
}

export fn basic_round(x: f64) callconv(.c) f64 {
    return round(x);
}

export fn basic_copysign(x: f64, y: f64) callconv(.c) f64 {
    return copysign(x, y);
}

export fn basic_erf(x: f64) callconv(.c) f64 {
    return erf(x);
}

export fn basic_erfc(x: f64) callconv(.c) f64 {
    return erfc(x);
}

export fn basic_tgamma(x: f64) callconv(.c) f64 {
    return tgamma(x);
}

export fn basic_lgamma(x: f64) callconv(.c) f64 {
    return lgamma(x);
}

export fn basic_nextafter(x: f64, y: f64) callconv(.c) f64 {
    return nextafter(x, y);
}

export fn basic_fmax(x: f64, y: f64) callconv(.c) f64 {
    return fmax(x, y);
}

export fn basic_fmin(x: f64, y: f64) callconv(.c) f64 {
    return fmin(x, y);
}

export fn basic_fma(x: f64, y: f64, z: f64) callconv(.c) f64 {
    return fma(x, y, z);
}

// =========================================================================
// Angle Conversion
// =========================================================================

export fn basic_deg(radians: f64) callconv(.c) f64 {
    return radians * (180.0 / M_PI);
}

export fn basic_rad(degrees: f64) callconv(.c) f64 {
    return degrees * (M_PI / 180.0);
}

// =========================================================================
// Statistical / Special Functions
// =========================================================================

export fn basic_sigmoid(x: f64) callconv(.c) f64 {
    return 1.0 / (1.0 + exp(-x));
}

export fn basic_logit(x: f64) callconv(.c) f64 {
    if (x <= 0.0 or x >= 1.0) {
        basic_error_msg("LOGIT domain error (0<x<1)");
        return 0.0;
    }
    return log(x / (1.0 - x));
}

export fn basic_normpdf(x: f64) callconv(.c) f64 {
    const inv_sqrt_2pi: f64 = 0.3989422804014327; // 1/sqrt(2*pi)
    return inv_sqrt_2pi * exp(-0.5 * x * x);
}

export fn basic_normcdf(x: f64) callconv(.c) f64 {
    return 0.5 * (1.0 + erf(x / M_SQRT2));
}

// =========================================================================
// Combinatorics
// =========================================================================

export fn basic_fact(n: f64) callconv(.c) f64 {
    if (n < 0.0) {
        basic_error_msg("FACTORIAL of negative number");
        return 0.0;
    }
    if (n > 170.0) {
        basic_error_msg("FACTORIAL overflow");
        return 0.0;
    }
    return tgamma(n + 1.0);
}

export fn basic_comb(n: f64, k: f64) callconv(.c) f64 {
    if (k < 0.0 or n < 0.0 or k > n) {
        basic_error_msg("COMB domain error");
        return 0.0;
    }
    return floor(0.5 + exp(lgamma(n + 1.0) - lgamma(k + 1.0) - lgamma(n - k + 1.0)));
}

export fn basic_perm(n: f64, k: f64) callconv(.c) f64 {
    if (k < 0.0 or n < 0.0 or k > n) {
        basic_error_msg("PERM domain error");
        return 0.0;
    }
    return floor(0.5 + exp(lgamma(n + 1.0) - lgamma(n - k + 1.0)));
}

// =========================================================================
// Clamping / Interpolation
// =========================================================================

export fn basic_clamp(x: f64, minv: f64, maxv: f64) callconv(.c) f64 {
    var lo = minv;
    var hi = maxv;
    if (lo > hi) {
        const tmp = lo;
        lo = hi;
        hi = tmp;
    }
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

export fn basic_lerp(a: f64, b: f64, t: f64) callconv(.c) f64 {
    return a + (b - a) * t;
}

// =========================================================================
// Financial Functions
// =========================================================================

export fn basic_pmt(rate: f64, nper: f64, pv: f64) callconv(.c) f64 {
    if (nper <= 0.0) {
        basic_error_msg("PMT nper must be > 0");
        return 0.0;
    }
    if (fabs(rate) < 1e-12) {
        return -(pv) / nper;
    }
    const r1 = pow(1.0 + rate, nper);
    return -(pv * rate * r1) / (r1 - 1.0);
}

export fn basic_pv(rate: f64, nper: f64, pmt_val: f64) callconv(.c) f64 {
    if (nper <= 0.0) {
        basic_error_msg("PV nper must be > 0");
        return 0.0;
    }
    if (fabs(rate) < 1e-12) {
        return -(pmt_val) * nper;
    }
    const r1 = pow(1.0 + rate, nper);
    return -pmt_val * (r1 - 1.0) / (rate * r1);
}

export fn basic_fv(rate: f64, nper: f64, pmt_val: f64) callconv(.c) f64 {
    if (nper <= 0.0) {
        basic_error_msg("FV nper must be > 0");
        return 0.0;
    }
    if (fabs(rate) < 1e-12) {
        return -(pmt_val) * nper;
    }
    const r1 = pow(1.0 + rate, nper);
    return -pmt_val * (r1 - 1.0) / rate;
}

// =========================================================================
// Random Number Generation
// =========================================================================

var rng_initialized: bool = false;

export fn basic_rnd() callconv(.c) f64 {
    if (!rng_initialized) {
        srand(@intCast(time(null)));
        rng_initialized = true;
    }
    return @as(f64, @floatFromInt(rand())) / @as(f64, @floatFromInt(RAND_MAX));
}

export fn basic_rnd_int(min_val: i32, max_val: i32) callconv(.c) i32 {
    if (!rng_initialized) {
        srand(@intCast(time(null)));
        rng_initialized = true;
    }

    var lo = min_val;
    var hi = max_val;
    if (lo > hi) {
        const tmp = lo;
        lo = hi;
        hi = tmp;
    }

    const range: i32 = hi - lo + 1;
    return lo + @mod(rand(), range);
}

export fn basic_randomize(seed: i32) callconv(.c) void {
    srand(@intCast(seed));
    rng_initialized = true;
}

export fn basic_rand(n: i32) callconv(.c) i32 {
    if (n <= 0) return 0;
    return @mod(rand(), n);
}

// =========================================================================
// Integer and Sign Functions
// =========================================================================

export fn basic_int(x: f64) callconv(.c) i32 {
    // INT() in BASIC truncates towards negative infinity (floor)
    return @intFromFloat(floor(x));
}

export fn basic_sgn(x: f64) callconv(.c) i32 {
    if (x < 0.0) return -1;
    if (x > 0.0) return 1;
    return 0;
}

export fn basic_fix(x: f64) callconv(.c) i32 {
    // FIX() in BASIC truncates towards zero
    return @intFromFloat(x);
}

export fn math_cint(x: f64) callconv(.c) i32 {
    // CINT() in BASIC rounds to nearest integer
    return @intFromFloat(round(x));
}
