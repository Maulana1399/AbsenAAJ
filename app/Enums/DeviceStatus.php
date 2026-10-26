<?php

namespace App\Enums;

enum DeviceStatus: string
{
    case ACTIVE = 'ACTIVE';
    case REVOKED = 'REVOKED';
}
