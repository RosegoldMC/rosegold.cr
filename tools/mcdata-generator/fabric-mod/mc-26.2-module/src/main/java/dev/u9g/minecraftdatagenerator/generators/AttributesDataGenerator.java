package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.ai.attributes.Attribute;
import net.minecraft.world.entity.ai.attributes.RangedAttribute;

import java.util.Objects;

public class AttributesDataGenerator implements IDataGenerator {
    @Override
    public String getDataName() {
        return "attributes";
    }

    @Override
    public JsonElement generateDataJson() {
        JsonArray arr = new JsonArray();
        var registry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.ATTRIBUTE);
        for (Attribute attribute : registry) {
            JsonObject obj = new JsonObject();
            String name = Objects.requireNonNull(registry.getKey(attribute)).getPath();
            while(name.contains("_")) {
                name = name.replaceFirst("_[a-z]", String.valueOf(Character.toUpperCase(name.charAt(name.indexOf("_") + 1))));
            }
            obj.addProperty("name", name);
            obj.addProperty("resource", Objects.requireNonNull(registry.getKey(attribute)).toString());
            obj.addProperty("min", ((RangedAttribute) attribute).getMinValue());
            obj.addProperty("max", ((RangedAttribute) attribute).getMaxValue());
            obj.addProperty("default", attribute.getDefaultValue());
            arr.add(obj);
        }
        return arr;
    }
}
