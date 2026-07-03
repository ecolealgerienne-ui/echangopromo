import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';

export enum OtpPurpose {
  INSCRIPTION = 'inscription',
  REVENDICATION = 'revendication',
  PIN_OUBLIE = 'pin_oublie',
}

/** Code OTP SMS — seuls cas d'usage : inscription initiale et PIN oublié (§3.2). */
@Entity()
export class OtpCode {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  telephone: string;

  @Exclude()
  @Column()
  codeHash: string;

  @Column({ type: 'enum', enum: OtpPurpose })
  purpose: OtpPurpose;

  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  @Column({ type: 'timestamptz', nullable: true })
  consumedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;
}
