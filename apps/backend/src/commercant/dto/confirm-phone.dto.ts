import { IsPhoneNumber, IsString, Length, Matches } from 'class-validator';

export class ConfirmPhoneDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @IsString()
  @Length(6, 6)
  code: string;

  @Matches(/^\d{4,6}$/, { message: 'Le code PIN doit contenir 4 à 6 chiffres' })
  pin: string;
}
