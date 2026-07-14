import { IsPhoneNumber, Matches } from 'class-validator';
import { PIN_VERIFY_MESSAGE, PIN_VERIFY_PATTERN } from '../pin.constants';

export class LoginCommercantDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @Matches(PIN_VERIFY_PATTERN, { message: PIN_VERIFY_MESSAGE })
  pin: string;
}
