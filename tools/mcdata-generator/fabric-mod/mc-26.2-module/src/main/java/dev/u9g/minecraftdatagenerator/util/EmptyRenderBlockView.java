package dev.u9g.minecraftdatagenerator.util;

import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.level.BlockAndTintGetter;
import net.minecraft.world.level.LightLayer;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeSpecialEffects.GrassColorModifier;
import net.minecraft.world.level.biome.Biomes;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.lighting.LevelLightEngine;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.level.material.Fluids;
import org.jetbrains.annotations.Nullable;

public enum EmptyRenderBlockView implements BlockAndTintGetter {
    INSTANCE;

    @Nullable
    public BlockEntity getBlockEntity(BlockPos pos) {
        return null;
    }

    public BlockState getBlockState(BlockPos pos) {
        return Blocks.AIR.defaultBlockState();
    }

    public FluidState getFluidState(BlockPos pos) {
        return Fluids.EMPTY.defaultFluidState();
    }

    public int getBottomY() {
        return 0;
    }

    @Override
    public int getHeight() {
        return 384;
    }

    @Override
    public float getShade(Direction direction, boolean shaded) {
        return 0.0f;
    }

    @Override
    public LevelLightEngine getLightEngine() {
        return null;
    }

    @Override
    public int getBlockTint(BlockPos pos, net.minecraft.world.level.ColorResolver colorResolver) {
        Registry<Biome> biomeRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.BIOME);
        Biome plainsBiome = biomeRegistry.get(Biomes.PLAINS).orElse(null).value();

        return colorResolver.getColor(plainsBiome, pos.getX(), pos.getY());
    }

    @Override
    public int getBrightness(LightLayer type, BlockPos pos) {
        return type == LightLayer.SKY ? 15 : 0;
    }

    public int getBaseLightLevel(BlockPos pos, int ambientDarkness) {
        return ambientDarkness;
    }

    @Override
    public int getMinY() {
        return -64;
    }
}
