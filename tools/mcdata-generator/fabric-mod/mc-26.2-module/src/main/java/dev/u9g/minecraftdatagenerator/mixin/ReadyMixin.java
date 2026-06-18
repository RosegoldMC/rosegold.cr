package dev.u9g.minecraftdatagenerator.mixin;

import dev.u9g.minecraftdatagenerator.MinecraftDataGenerator;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.SharedConstants;
import net.minecraft.server.dedicated.DedicatedServer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(DedicatedServer.class)
public class ReadyMixin {

    @Inject(method = "initServer()Z", at = @At("TAIL"))
    private void init(CallbackInfoReturnable<Boolean> cir) {
        MinecraftDataGenerator.start(
                SharedConstants.getCurrentVersion().name(),
                DGU.getCurrentlyRunningServer().getServerDirectory()
        );
    }
}
