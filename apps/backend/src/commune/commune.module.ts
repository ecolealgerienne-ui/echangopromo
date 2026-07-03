import { Module } from '@nestjs/common';
import { CommuneController } from './commune.controller';
import { CommuneService } from './commune.service';

@Module({
  controllers: [CommuneController],
  providers: [CommuneService],
  exports: [CommuneService],
})
export class CommuneModule {}
