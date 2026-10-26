<?php

namespace App\Filament\Resources\AttendanceEvents\Tables;

use App\Enums\AttendanceEventType;
use App\Enums\AttendanceStatus;
use App\Models\AttendanceEvent;
use Filament\Actions\Action;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Storage;

class AttendanceEventsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('employee.name')
                    ->label('Karyawan')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('employee.employee_number')
                    ->label('No. Karyawan')
                    ->searchable(),
                TextColumn::make('employee.branch.name')
                    ->label('Cabang')
                    ->placeholder('—'),
                TextColumn::make('event_type')
                    ->label('Tipe')
                    ->badge()
                    ->formatStateUsing(fn (AttendanceEventType $state) => $state->value),
                TextColumn::make('status')
                    ->label('Status')
                    ->badge()
                    ->color(fn (AttendanceStatus $state): string => match ($state) {
                        AttendanceStatus::ON_TIME, AttendanceStatus::NORMAL => 'success',
                        AttendanceStatus::LATE => 'warning',
                        AttendanceStatus::EARLY_CHECKOUT, AttendanceStatus::MISSING_CHECKOUT => 'danger',
                    })
                    ->formatStateUsing(fn (AttendanceStatus $state) => $state->value),
                TextColumn::make('event_at')
                    ->label('Waktu Event')
                    ->dateTime('d M Y H:i:s'),
                TextColumn::make('latitude')
                    ->label('Lat')
                    ->placeholder('—'),
                TextColumn::make('longitude')
                    ->label('Lng')
                    ->placeholder('—'),
                TextColumn::make('accuracy_meters')
                    ->label('Akurasi (m)')
                    ->placeholder('—'),
                TextColumn::make('distance_meters')
                    ->label('Jarak (m)')
                    ->placeholder('—'),
                TextColumn::make('location_valid')
                    ->label('Lokasi Valid')
                    ->badge()
                    ->formatStateUsing(fn (?bool $state) => $state ? 'VALID' : 'INVALID')
                    ->color(fn (?bool $state) => $state ? 'success' : 'danger'),
                TextColumn::make('photo.mime_type')
                    ->label('Foto Tipe')
                    ->placeholder('—'),
                TextColumn::make('photo.file_size')
                    ->label('Foto Ukuran')
                    ->formatStateUsing(fn (?int $state) => $state !== null ? number_format($state) : '—'),
                TextColumn::make('photo.sha256')
                    ->label('Foto SHA-256')
                    ->limit(12)
                    ->placeholder('—')
                    ->copyable(),
                TextColumn::make('device.device_uuid')
                    ->label('Device')
                    ->placeholder('—')
                    ->searchable(),
                TextColumn::make('sync_source')
                    ->label('Sumber')
                    ->formatStateUsing(fn (?string $state) => $state ?? 'mobile'),
            ])
            ->recordActions([
                Action::make('viewPhoto')
                    ->label('Lihat Foto')
                    ->icon(Heroicon::OutlinedPhoto)
                    ->modalHeading('Foto Selfie')
                    ->modalSubmitAction(false)
                    ->modalCancelActionLabel('Tutup')
                    ->modalContent(function (AttendanceEvent $record) {
                        $photo = $record->photo;

                        $url = $photo !== null && Storage::disk('local')->exists($photo->storage_path)
                            ? route('admin.attendance-events.photo', $record)
                            : null;

                        return view('filament.attendance-events.photo-preview', [
                            'photo' => $photo,
                            'url' => $url,
                        ]);
                    }),
            ])
            ->filters([
                SelectFilter::make('event_type')
                    ->options(AttendanceEventType::class),
                SelectFilter::make('status')
                    ->options(AttendanceStatus::class),
                SelectFilter::make('location_valid')
                    ->label('Lokasi Valid')
                    ->options([
                        '1' => 'VALID',
                        '0' => 'INVALID',
                    ]),
            ])
            ->defaultSort('event_at', 'desc');
    }
}
