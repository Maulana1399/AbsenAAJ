<?php

namespace App\Filament\Resources\Employees\Tables;

use App\Enums\EmployeeStatus;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteAction;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Actions\ForceDeleteBulkAction;
use Filament\Actions\RestoreBulkAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;

class EmployeesTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('employee_number')
                    ->label('No. Karyawan')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('name')
                    ->label('Nama')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('phone')
                    ->label('No. Telepon')
                    ->searchable(),
                TextColumn::make('branch.name')
                    ->label('Cabang')
                    ->placeholder('—'),
                TextColumn::make('user.email')
                    ->label('Akun Login')
                    ->placeholder('—'),
                TextColumn::make('status')
                    ->label('Status')
                    ->badge()
                    ->formatStateUsing(fn (EmployeeStatus $state) => $state->value),
                TextColumn::make('joined_at')
                    ->label('Bergabung')
                    ->date('d M Y'),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->options(EmployeeStatus::class),
                TrashedFilter::make(),
            ])
            ->recordActions([
                EditAction::make(),
                DeleteAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                    RestoreBulkAction::make(),
                    ForceDeleteBulkAction::make(),
                ]),
            ]);
    }
}
