<?php

namespace App\Filament\Resources\Branches\Schemas;

use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Schemas\Schema;

class BranchForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('code')
                    ->label('Kode')
                    ->required()
                    ->unique(ignoreRecord: true)
                    ->maxLength(50),
                TextInput::make('name')
                    ->label('Nama')
                    ->required()
                    ->maxLength(255),
                TextInput::make('latitude')
                    ->label('Latitude')
                    ->numeric()
                    ->minValue(-90)
                    ->maxValue(90)
                    ->step('0.0000001'),
                TextInput::make('longitude')
                    ->label('Longitude')
                    ->numeric()
                    ->minValue(-180)
                    ->maxValue(180)
                    ->step('0.0000001'),
                TextInput::make('radius_meters')
                    ->label('Radius (meter)')
                    ->numeric()
                    ->integer()
                    ->minValue(1)
                    ->maxValue(100000)
                    ->default(100),
                Select::make('timezone')
                    ->label('Zona Waktu')
                    ->options([
                        'Asia/Jakarta' => 'Asia/Jakarta (WIB)',
                        'Asia/Pontianak' => 'Asia/Pontianak (WIB)',
                        'Asia/Makassar' => 'Asia/Makassar (WITA)',
                        'Asia/Jayapura' => 'Asia/Jayapura (WIT)',
                    ])
                    ->default('Asia/Makassar')
                    ->searchable()
                    ->required(),
                Toggle::make('is_active')
                    ->label('Aktif')
                    ->default(true),
            ]);
    }
}
