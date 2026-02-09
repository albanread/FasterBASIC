//
// math_ops.c
// FasterBASIC QBE Runtime Library - Math Operations
//
// This file implements mathematical functions for BASIC programs.
//

#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

// =============================================================================
// Absolute Value
// =============================================================================

int32_t basic_abs_int(int32_t x) {
    return x < 0 ? -x : x;
}

double basic_abs_double(double x) {
    return fabs(x);
}

// =============================================================================
// Square Root
// =============================================================================

double basic_sqrt(double x) {
    if (x < 0.0) {
        basic_error_msg("Square root of negative number");
        return 0.0;
    }
    return sqrt(x);
}

// =============================================================================
// Power
// =============================================================================

double basic_pow(double base, double exponent) {
    // Handle special cases
    if (base == 0.0 && exponent < 0.0) {
        basic_error_msg("Division by zero in power operation");
        return 0.0;
    }
    
    return pow(base, exponent);
}

// =============================================================================
// Extended Exponentials and Logarithms
// =============================================================================

double basic_exp2(double x) {
    return exp2(x);
}

double basic_expm1(double x) {
    return expm1(x);
}

double basic_log10(double x) {
    if (x <= 0.0) {
        basic_error_msg("Logarithm base 10 of non-positive number");
        return 0.0;
    }
    return log10(x);
}

double basic_log1p(double x) {
    if (x <= -1.0) {
        basic_error_msg("Logarithm of 1 + x with x <= -1");
        return 0.0;
    }
    return log1p(x);
}

// =============================================================================
// Trigonometric Functions
// =============================================================================

double basic_sin(double x) {
    return sin(x);
}

double basic_cos(double x) {
    return cos(x);
}

double basic_tan(double x) {
    return tan(x);
}

double basic_asin(double x) {
    if (x < -1.0 || x > 1.0) {
        basic_error_msg("ASIN domain error");
        return 0.0;
    }
    return asin(x);
}

double basic_acos(double x) {
    if (x < -1.0 || x > 1.0) {
        basic_error_msg("ACOS domain error");
        return 0.0;
    }
    return acos(x);
}

double basic_atan(double x) {
    return atan(x);
}

double basic_atan2(double y, double x) {
    return atan2(y, x);
}

// Hyperbolic functions
double basic_sinh(double x) {
    return sinh(x);
}

double basic_cosh(double x) {
    return cosh(x);
}

double basic_tanh(double x) {
    return tanh(x);
}

double basic_asinh(double x) {
    return asinh(x);
}

double basic_acosh(double x) {
    if (x < 1.0) {
        basic_error_msg("ACOSH domain error");
        return 0.0;
    }
    return acosh(x);
}

double basic_atanh(double x) {
    if (x <= -1.0 || x >= 1.0) {
        basic_error_msg("ATANH domain error");
        return 0.0;
    }
    return atanh(x);
}

// =============================================================================
// Logarithm and Exponential
// =============================================================================

double basic_log(double x) {
    if (x <= 0.0) {
        basic_error_msg("Logarithm of non-positive number");
        return 0.0;
    }
    return log(x);
}

double basic_exp(double x) {
    return exp(x);
}

// =============================================================================
// Power Helpers and Roots
// =============================================================================

double basic_cbrt(double x) {
    return cbrt(x);
}

double basic_hypot(double x, double y) {
    return hypot(x, y);
}

double basic_fmod(double x, double y) {
    if (y == 0.0) {
        basic_error_msg("FMOD division by zero");
        return 0.0;
    }
    return fmod(x, y);
}

double basic_remainder(double x, double y) {
    if (y == 0.0) {
        basic_error_msg("REMAINDER division by zero");
        return 0.0;
    }
    return remainder(x, y);
}

double basic_floor(double x) {
    return floor(x);
}

double basic_ceil(double x) {
    return ceil(x);
}

double basic_trunc(double x) {
    return trunc(x);
}

double basic_round(double x) {
    return round(x);
}

double basic_copysign(double x, double y) {
    return copysign(x, y);
}

double basic_erf(double x) {
    return erf(x);
}

double basic_erfc(double x) {
    return erfc(x);
}

double basic_tgamma(double x) {
    return tgamma(x);
}

double basic_lgamma(double x) {
    return lgamma(x);
}

double basic_nextafter(double x, double y) {
    return nextafter(x, y);
}

double basic_fmax(double x, double y) {
    return fmax(x, y);
}

double basic_fmin(double x, double y) {
    return fmin(x, y);
}

double basic_fma(double x, double y, double z) {
    return fma(x, y, z);
}

double basic_deg(double radians) {
    return radians * (180.0 / M_PI);
}

double basic_rad(double degrees) {
    return degrees * (M_PI / 180.0);
}

double basic_sigmoid(double x) {
    return 1.0 / (1.0 + exp(-x));
}

double basic_logit(double x) {
    if (x <= 0.0 || x >= 1.0) {
        basic_error_msg("LOGIT domain error (0<x<1)");
        return 0.0;
    }
    return log(x / (1.0 - x));
}

double basic_normpdf(double x) {
    const double inv_sqrt_2pi = 0.3989422804014327; // 1/sqrt(2*pi)
    return inv_sqrt_2pi * exp(-0.5 * x * x);
}

double basic_normcdf(double x) {
    // Standard normal CDF via erf
    return 0.5 * (1.0 + erf(x / M_SQRT2));
}

double basic_fact(double n) {
    if (n < 0.0) {
        basic_error_msg("FACTORIAL of negative number");
        return 0.0;
    }
    if (n > 170.0) {
        basic_error_msg("FACTORIAL overflow");
        return 0.0;
    }
    // Use gamma(n+1)
    return tgamma(n + 1.0);
}

double basic_comb(double n, double k) {
    if (k < 0.0 || n < 0.0 || k > n) {
        basic_error_msg("COMB domain error");
        return 0.0;
    }
    return floor(0.5 + exp(lgamma(n + 1.0) - lgamma(k + 1.0) - lgamma(n - k + 1.0)));
}

double basic_perm(double n, double k) {
    if (k < 0.0 || n < 0.0 || k > n) {
        basic_error_msg("PERM domain error");
        return 0.0;
    }
    return floor(0.5 + exp(lgamma(n + 1.0) - lgamma(n - k + 1.0)));
}

double basic_clamp(double x, double minv, double maxv) {
    if (minv > maxv) {
        double tmp = minv; minv = maxv; maxv = tmp;
    }
    if (x < minv) return minv;
    if (x > maxv) return maxv;
    return x;
}

double basic_lerp(double a, double b, double t) {
    return a + (b - a) * t;
}

double basic_pmt(double rate, double nper, double pv) {
    if (nper <= 0.0) {
        basic_error_msg("PMT nper must be > 0");
        return 0.0;
    }
    if (fabs(rate) < 1e-12) {
        return -(pv) / nper;
    }
    double r1 = pow(1.0 + rate, nper);
    return -(pv * rate * r1) / (r1 - 1.0);
}

double basic_pv(double rate, double nper, double pmt) {
    if (nper <= 0.0) {
        basic_error_msg("PV nper must be > 0");
        return 0.0;
    }
    if (fabs(rate) < 1e-12) {
        return -(pmt) * nper;
    }
    double r1 = pow(1.0 + rate, nper);
    return -pmt * (r1 - 1.0) / (rate * r1);
}

double basic_fv(double rate, double nper, double pmt) {
    if (nper <= 0.0) {
        basic_error_msg("FV nper must be > 0");
        return 0.0;
    }
    if (fabs(rate) < 1e-12) {
        return -(pmt) * nper;
    }
    double r1 = pow(1.0 + rate, nper);
    return -pmt * (r1 - 1.0) / rate;
}

// =============================================================================
// Random Number Generation
// =============================================================================

static bool rng_initialized = false;

double basic_rnd(void) {
    if (!rng_initialized) {
        srand((unsigned int)time(NULL));
        rng_initialized = true;
    }
    
    // Return random number between 0.0 and 1.0
    return (double)rand() / (double)RAND_MAX;
}

int32_t basic_rnd_int(int32_t min, int32_t max) {
    if (!rng_initialized) {
        srand((unsigned int)time(NULL));
        rng_initialized = true;
    }
    
    if (min > max) {
        int32_t temp = min;
        min = max;
        max = temp;
    }
    
    // Generate random integer in range [min, max]
    int32_t range = max - min + 1;
    return min + (rand() % range);
}

void basic_randomize(int32_t seed) {
    srand((unsigned int)seed);
    rng_initialized = true;
}

// Get random integer from 0 to n-1 (BASIC RAND function)
int32_t basic_rand(int32_t n) {
    if (n <= 0) return 0;
    return rand() % n;
}

// =============================================================================
// Integer and Sign Functions
// =============================================================================

int32_t basic_int(double x) {
    // INT() in BASIC truncates towards negative infinity (floor)
    return (int32_t)floor(x);
}

int32_t basic_sgn(double x) {
    if (x < 0.0) return -1;
    if (x > 0.0) return 1;
    return 0;
}

int32_t basic_fix(double x) {
    // FIX() in BASIC truncates towards zero
    return (int32_t)x;
}

int32_t math_cint(double x) {
    // CINT() in BASIC rounds to nearest integer
    return (int32_t)round(x);
}