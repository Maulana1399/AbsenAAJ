<?php

namespace App\Enums;

enum UserRole: string
{
    case ADMIN = 'ADMIN';
    case HR = 'HR';
    case EMPLOYEE = 'EMPLOYEE';
}
