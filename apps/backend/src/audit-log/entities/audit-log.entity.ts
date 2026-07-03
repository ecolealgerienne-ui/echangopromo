import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';

export enum AuditActorType {
  AGENT = 'agent',
  ADMIN = 'admin',
}

/** Traçabilité des actions agent/admin — utile pour zones multiples et transferts (specs §4). */
@Entity()
export class AuditLog {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'enum', enum: AuditActorType })
  actorType: AuditActorType;

  @Column()
  actorId: string;

  @Column()
  action: string;

  @Column({ type: 'varchar', nullable: true })
  targetType: string | null;

  @Column({ type: 'varchar', nullable: true })
  targetId: string | null;

  @Column({ type: 'jsonb', nullable: true })
  metadata: Record<string, unknown> | null;

  @CreateDateColumn()
  createdAt: Date;
}
