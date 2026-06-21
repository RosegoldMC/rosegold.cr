package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Registry;
import net.minecraft.core.RegistryAccess;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.tags.BiomeTags;
import net.minecraft.world.attribute.EnvironmentAttributes;
import net.minecraft.world.attribute.EnvironmentAttributeMap;
import net.minecraft.world.level.biome.Biome;

public class BiomesDataGenerator implements IDataGenerator {
    private static String guessBiomeDimensionFromCategory(Biome biome) {
        var biomeRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.BIOME);
        if (biomeRegistry.wrapAsHolder(biome).is(BiomeTags.IS_NETHER)) {
            return "nether";
        } else if (biomeRegistry.wrapAsHolder(biome).is(BiomeTags.IS_END)) {
            return "end";
        } else {
            return "overworld";
        }
    }

    private static String guessCategoryBasedOnName(String name, String dimension) {
        if (dimension.equals("nether")) {
            return "nether";
        } else if (dimension.equals("end")) {
            return "the_end";
        }

        if (name.contains("end")) {
            System.out.println();
        }

        if (name.contains("hills")) {
            return "extreme_hills";
        } else if (name.contains("ocean")) {
            return "ocean";
        } else if (name.contains("plains")) {
            return "plains";
        } else if (name.contains("ice") || name.contains("frozen")) {
            return "ice";
        } else if (name.contains("jungle")) {
            return "jungle";
        } else if (name.contains("desert")) {
            return "desert";
        } else if (name.contains("forest") || name.contains("grove")) {
            return "forest";
        } else if (name.contains("taiga")) {
            return "taiga";
        } else if (name.contains("swamp")) {
            return "swamp";
        } else if (name.contains("river")) {
            return "river";
        } else if (name.equals("the_end")) {
            return "the_end";
        } else if (name.contains("mushroom")) {
            return "mushroom";
        } else if (name.contains("beach") || name.equals("stony_shore")) {
            return "beach";
        } else if (name.contains("savanna")) {
            return "savanna";
        } else if (name.contains("badlands")) {
            return "mesa";
        } else if (name.contains("peaks") || name.equals("snowy_slopes") || name.equals("meadow")) {
            return "mountain";
        } else if (name.equals("the_void")) {
            return "none";
        } else if (name.contains("cave") || name.equals("deep_dark")) {
            return "underground";
        } else {
            System.out.println("Unable to find biome category for biome with name: '" + name + "'");
            return "none";
        }
    }

    public static JsonObject generateBiomeInfo(Registry<Biome> registry, Biome biome) {
        JsonObject biomeDesc = new JsonObject();
        Identifier registryKey = registry.getKey(biome);
        String localizationKey = String.format("biome.%s.%s", registryKey.getNamespace(), registryKey.getPath());
        String name = registryKey.getPath();
        biomeDesc.addProperty("id", registry.getId(biome));
        biomeDesc.addProperty("name", name);
        String dimension = guessBiomeDimensionFromCategory(biome);
        biomeDesc.addProperty("category", guessCategoryBasedOnName(name, dimension));
        biomeDesc.addProperty("temperature", biome.getBaseTemperature());
        //biomeDesc.addProperty("precipitation", biome.getPrecipitation().getName());// - removed in 1.19.4
        biomeDesc.addProperty("has_precipitation", biome.hasPrecipitation());
        //biomeDesc.addProperty("depth", biome.getDepth()); - Doesn't exist anymore in minecraft source
        biomeDesc.addProperty("dimension", dimension);
        biomeDesc.addProperty("displayName", DGU.translateText(localizationKey));
        // In 1.21.11, sky color moved to EnvironmentAttributes
        EnvironmentAttributeMap.Entry<Integer, ?> skyColorEntry = biome.getAttributes().get(EnvironmentAttributes.SKY_COLOR);
        int skyColor = 0;
        if (skyColorEntry != null && skyColorEntry.argument() instanceof Integer) {
            // convert to RGB
            skyColor = (Integer) skyColorEntry.argument() & 0xFFFFFF;
        }
        biomeDesc.addProperty("color", skyColor);
        //biomeDesc.addProperty("rainfall", biome.getDownfall());// - removed in 1.19.4

        return biomeDesc;
    }

    @Override
    public String getDataName() {
        return "biomes";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray biomesArray = new JsonArray();
        RegistryAccess registryManager = DGU.getWorld().registryAccess();
        Registry<Biome> biomeRegistry = registryManager.lookupOrThrow(Registries.BIOME);

        biomeRegistry.stream()
                .map(biome -> generateBiomeInfo(biomeRegistry, biome))
                .forEach(biomesArray::add);
        return biomesArray;
    }
}
