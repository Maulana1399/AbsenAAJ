<?php

namespace App\Enums;

enum AttendanceEventType: string
{
    case CHECK_IN = 'CHECK_IN';
    case CHECK_OUT = 'CHECK_OUT';
}
