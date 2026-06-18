package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Registry;
import net.minecraft.core.particles.ParticleType;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;

public class ParticlesDataGenerator implements IDataGenerator {
    public static JsonObject generateParticleType(Registry<ParticleType<?>> registry, ParticleType<?> particleType) {
        JsonObject effectDesc = new JsonObject();
        Identifier registryKey = registry.getKey(particleType);

        effectDesc.addProperty("id", registry.getId(particleType));
        effectDesc.addProperty("name", registryKey.getPath());
        return effectDesc;
    }

    @Override
    public String getDataName() {
        return "particles";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray resultsArray = new JsonArray();
        Registry<ParticleType<?>> particleTypeRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.PARTICLE_TYPE);
        particleTypeRegistry.forEach(particleType -> resultsArray.add(generateParticleType(particleTypeRegistry, particleType)));
        return resultsArray;
    }
}
