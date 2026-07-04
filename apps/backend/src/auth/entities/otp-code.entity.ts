import { Exclude } from 'class-transformer';
import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

export enum OtpPurpose {
  INSCRIPTION = 'inscription',
  REVENDICATION = 'revendication',
  PIN_OUBLIE = 'pin_oublie',
}

/** Code OTP SMS — seuls cas d'usage : inscription initiale et PIN oublié (§3.2). */
@Entity()
@Index(['telephone', 'purpose'])
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

  /** Tentatives de vérification échouées — verrouille le code après un seuil (anti brute-force). */
  @Column({ default: 0 })
  attempts: number;

  @CreateDateColumn()
  createdAt: Date;
}
