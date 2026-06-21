package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.sounds.SoundEvent;

public class SoundsDataGenerator implements IDataGenerator {
    public static JsonObject generateSound(SoundEvent soundEvent) {
        JsonObject soundDesc = new JsonObject();

        soundDesc.addProperty("id", BuiltInRegistries.SOUND_EVENT.getId(soundEvent) + 1); // the plus 1 is required for 1.19.2+ due to Mojang using 0 in the packet to say that you should read a string id instead.
        soundDesc.addProperty("name", soundEvent.location().getPath());

        return soundDesc;
    }

    @Override
    public String getDataName() {
        return "sounds";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray resultsArray = new JsonArray();
        Registry<SoundEvent> soundEventRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.SOUND_EVENT);
        soundEventRegistry.forEach(sound -> resultsArray.add(generateSound(sound)));
        return resultsArray;
    }
}
