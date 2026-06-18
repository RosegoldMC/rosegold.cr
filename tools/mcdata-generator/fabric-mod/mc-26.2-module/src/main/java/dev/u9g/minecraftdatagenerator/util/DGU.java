package dev.u9g.minecraftdatagenerator.util;

import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.locale.Language;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.Level;

public class DGU {
    @SuppressWarnings("deprecation")
    public static MinecraftServer getCurrentlyRunningServer() {
        return (MinecraftServer) FabricLoader.getInstance().getGameInstance();
    }

    public static String translateText(String translationKey) {
        return Language.getInstance().getOrDefault(translationKey);
    }

    public static Level getWorld() {
        return getCurrentlyRunningServer().overworld();
    }
}
