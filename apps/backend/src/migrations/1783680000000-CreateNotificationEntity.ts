import { MigrationInterface, QueryRunner, Table, TableIndex } from 'typeorm';

export class CreateNotificationEntity1783680000000 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.createTable(
      new Table({
        name: 'notification',
        columns: [
          {
            name: 'id',
            type: 'uuid',
            isPrimary: true,
            default: 'gen_random_uuid()',
          },
          {
            name: 'type',
            type: 'enum',
            enum: ['promo_warned', 'promo_hidden', 'promo_verified'],
          },
          {
            name: 'recipientType',
            type: 'enum',
            enum: ['commercant', 'agent', 'admin'],
          },
          {
            name: 'recipientId',
            type: 'uuid',
          },
          {
            name: 'promoId',
            type: 'uuid',
            isNullable: true,
          },
          {
            name: 'message',
            type: 'varchar',
          },
          {
            name: 'metadata',
            type: 'jsonb',
            isNullable: true,
          },
          {
            name: 'readAt',
            type: 'timestamptz',
            isNullable: true,
          },
          {
            name: 'createdAt',
            type: 'timestamptz',
            default: 'now()',
          },
          {
            name: 'updatedAt',
            type: 'timestamptz',
            default: 'now()',
          },
        ],
      }),
    );

    await queryRunner.createIndex(
      'notification',
      new TableIndex({
        name: 'IDX_notification_recipientType_recipientId_readAt',
        columnNames: ['recipientType', 'recipientId', 'readAt'],
      }),
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropTable('notification');
  }
}
