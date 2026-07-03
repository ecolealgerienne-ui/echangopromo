import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CommuneController } from './commune.controller';
import { CommuneService } from './commune.service';
import { Commune } from './entities/commune.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Commune])],
  controllers: [CommuneController],
  providers: [CommuneService],
  exports: [CommuneService],
})
export class CommuneModule {}
