<?php

namespace App\Filament\Resources\AttendanceEvents;

use App\Enums\AttendanceEventType;
use App\Filament\Resources\AttendanceEvents\Pages\ListAttendanceEvents;
use App\Filament\Resources\AttendanceEvents\Tables\AttendanceEventsTable;
use App\Models\AttendanceEvent;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;

class AttendanceEventResource extends Resource
{
    protected static ?string $model = AttendanceEvent::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedClipboardDocumentList;

    public static function table(Table $table): Table
    {
        return AttendanceEventsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListAttendanceEvents::route('/'),
        ];
    }

    public static function getNavigationLabel(): string
    {
        return 'Attendance';
    }

    public static function getNavigationGroup(): ?string
    {
        return 'HR';
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function getEventTypes(): array
    {
        return [
            AttendanceEventType::CHECK_IN->value => AttendanceEventType::CHECK_IN->value,
            AttendanceEventType::CHECK_OUT->value => AttendanceEventType::CHECK_OUT->value,
        ];
    }
}
