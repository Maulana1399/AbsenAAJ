<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Attendance timezone
    |--------------------------------------------------------------------------
    |
    | All work-hour calculations (shift start/end, grace period) are done in
    | this timezone. Timestamps are still stored in UTC internally.
    |
    */

    'timezone' => env('ATTENDANCE_TIMEZONE', 'Asia/Makassar'),

    /*
    |--------------------------------------------------------------------------
    | Default MVP shift
    |--------------------------------------------------------------------------
    |
    | A single simple shift used for status calculation. Shift schedules
    | (multi-shift, night shift) are intentionally out of scope for now.
    |
    */

    'shift' => [
        'start' => env('ATTENDANCE_SHIFT_START', '08:30'),
        'grace_minutes' => (int) env('ATTENDANCE_SHIFT_GRACE_MINUTES', 5),
        'end' => env('ATTENDANCE_SHIFT_END', '17:00'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Location bounds
    |--------------------------------------------------------------------------
    |
    | Events with a reported GPS accuracy worse than this value are rejected
    | with LOCATION_LOW_ACCURACY. This is distinct from being outside the
    | branch geofence (OUTSIDE_GEOFENCE).
    |
    */

    'location_max_accuracy_meters' => (int) env('ATTENDANCE_LOCATION_MAX_ACCURACY_METERS', 100),

    /*
    |--------------------------------------------------------------------------
    | Attendance photos
    |--------------------------------------------------------------------------
    |
    | Uploaded photos must be a Safe image MIME type, sized under the limit,
    | and are always stored on the private filesystem. The extension coming
    | from the client is never trusted.
    |
    */

    'photo' => [
        'max_kilobytes' => (int) env('ATTENDANCE_PHOTO_MAX_KB', 5120),
        'mime_types' => ['image/jpeg', 'image/png', 'image/webp'],
    ],

];
