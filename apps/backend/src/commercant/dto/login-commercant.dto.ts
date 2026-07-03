import { IsPhoneNumber, Matches } from 'class-validator';

export class LoginCommercantDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @Matches(/^\d{4,6}$/, { message: 'Le code PIN doit contenir 4 à 6 chiffres' })
  pin: string;
}
