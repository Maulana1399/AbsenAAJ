<?php

namespace App\Filament\Resources\AttendanceEvents\Pages;

use App\Filament\Resources\AttendanceEvents\AttendanceEventResource;
use Filament\Resources\Pages\ListRecords;

class ListAttendanceEvents extends ListRecords
{
    protected static string $resource = AttendanceEventResource::class;

    protected function getHeaderActions(): array
    {
        return [];
    }
}
