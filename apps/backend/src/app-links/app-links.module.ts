import { Module } from '@nestjs/common';
import { AppLinksController } from './app-links.controller';

@Module({
  controllers: [AppLinksController],
})
export class AppLinksModule {}
