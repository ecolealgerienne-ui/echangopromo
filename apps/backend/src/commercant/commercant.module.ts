import { Module } from '@nestjs/common';
import { CommercantController } from './commercant.controller';
import { CommercantService } from './commercant.service';

@Module({
  controllers: [CommercantController],
  providers: [CommercantService],
  exports: [CommercantService],
})
export class CommercantModule {}
