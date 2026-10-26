<?php

namespace App\Enums;

enum AttendanceStatus: string
{
    case ON_TIME = 'ON_TIME';
    case LATE = 'LATE';
    case NORMAL = 'NORMAL';
    case EARLY_CHECKOUT = 'EARLY_CHECKOUT';
    case MISSING_CHECKOUT = 'MISSING_CHECKOUT';
}
