<?php

namespace App\Filament\Resources\Employees\Schemas;

use App\Enums\EmployeeStatus;
use Filament\Forms\Components\DatePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;
use Illuminate\Database\Eloquent\Builder;

class EmployeeForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('employee_number')
                    ->label('No. Karyawan')
                    ->required()
                    ->unique(ignoreRecord: true)
                    ->maxLength(50),
                TextInput::make('name')
                    ->label('Nama')
                    ->required()
                    ->maxLength(255),
                TextInput::make('phone')
                    ->label('No. Telepon')
                    ->tel()
                    ->maxLength(20),
                Select::make('branch_id')
                    ->label('Cabang')
                    ->relationship(
                        name: 'branch',
                        titleAttribute: 'name',
                        modifyQueryUsing: fn (Builder $query): Builder => $query->where('is_active', true),
                    )
                    ->searchable()
                    ->preload(),
                Select::make('user_id')
                    ->label('Akun Login')
                    ->relationship('user', 'email')
                    ->searchable()
                    ->preload(),
                Select::make('status')
                    ->label('Status')
                    ->options(EmployeeStatus::class)
                    ->default(EmployeeStatus::ACTIVE->value)
                    ->required(),
                DatePicker::make('joined_at')
                    ->label('Tanggal Bergabung'),
            ]);
    }
}
