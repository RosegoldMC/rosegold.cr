package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.world.effect.MobEffect;
import net.minecraft.world.effect.MobEffects;
import org.apache.commons.lang3.StringUtils;

import java.util.Arrays;
import java.util.stream.Collectors;

public class EffectsDataGenerator implements IDataGenerator {
    public static JsonObject generateEffect(Registry<MobEffect> registry, MobEffect mobEffect) {
        JsonObject effectDesc = new JsonObject();
        Identifier registryKey = registry.getKey(mobEffect);

        effectDesc.addProperty("id", registry.getId(mobEffect));
        if (mobEffect == MobEffects.UNLUCK.value()) {
            effectDesc.addProperty("name", "BadLuck");
            effectDesc.addProperty("displayName", "Bad Luck");
        } else {
            effectDesc.addProperty("name", Arrays.stream(registryKey.getPath().split("_")).map(StringUtils::capitalize).collect(Collectors.joining()));
            effectDesc.addProperty("displayName", DGU.translateText(mobEffect.getDescriptionId()));
        }

        effectDesc.addProperty("type", mobEffect.isBeneficial() ? "good" : "bad");
        return effectDesc;
    }

    @Override
    public String getDataName() {
        return "effects";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray resultsArray = new JsonArray();
        Registry<MobEffect> mobEffectRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.MOB_EFFECT);
        mobEffectRegistry.forEach(effect -> resultsArray.add(generateEffect(mobEffectRegistry, effect)));
        return resultsArray;
    }
}
