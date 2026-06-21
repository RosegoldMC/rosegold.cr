package dev.u9g.minecraftdatagenerator.generators;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.u9g.minecraftdatagenerator.util.DGU;
import net.minecraft.core.Holder;
import net.minecraft.core.HolderSet;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.tags.TagKey;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.enchantment.Enchantment;

import java.util.List;

public class EnchantmentsDataGenerator implements IDataGenerator {
    public static String getEnchantmentTargetName(HolderSet<Item> target) {
        TagKey<Item> tagKey = target.unwrapKey().orElseThrow();
        return tagKey.location().getPath().split("/")[1];
    }

    private static boolean isEnchantmentInTag(Enchantment enchantment, String tag) {
        return DGU.getWorld()
                .registryAccess()
                .lookupOrThrow(Registries.ENCHANTMENT)
                .getOrThrow(TagKey.create(Registries.ENCHANTMENT, Identifier.parse(tag)))
                .stream()
                .anyMatch(enchantmentRegistryEntry -> enchantmentRegistryEntry.value() == enchantment);
    }

    //Equation enchantment costs follow is a * level + b, so we can easily retrieve a and b by passing zero level
    private static JsonObject generateEnchantmentMinPowerCoefficients(Enchantment enchantment) {
        int b = enchantment.getMinLevel();
        int a = enchantment.getMaxLevel() - b;

        JsonObject resultObject = new JsonObject();
        resultObject.addProperty("a", a);
        resultObject.addProperty("b", b);
        return resultObject;
    }

    private static JsonObject generateEnchantmentMaxPowerCoefficients(Enchantment enchantment) {
        int b = enchantment.getMinLevel();
        int a = enchantment.getMaxLevel() - b;

        JsonObject resultObject = new JsonObject();
        resultObject.addProperty("a", a);
        resultObject.addProperty("b", b);
        return resultObject;
    }

    public static JsonObject generateEnchantment(Registry<Enchantment> registry, Enchantment enchantment) {
        JsonObject enchantmentDesc = new JsonObject();
        Identifier registryKey = registry.getKey(enchantment);

        enchantmentDesc.addProperty("id", registry.getId(enchantment));
        enchantmentDesc.addProperty("name", registryKey.getPath());
        enchantmentDesc.addProperty("displayName", enchantment.description().getString());

        enchantmentDesc.addProperty("maxLevel", enchantment.getMaxLevel());
        enchantmentDesc.add("minCost", generateEnchantmentMinPowerCoefficients(enchantment));
        enchantmentDesc.add("maxCost", generateEnchantmentMaxPowerCoefficients(enchantment));

        enchantmentDesc.addProperty("treasureOnly", isEnchantmentInTag(enchantment, "treasure"));

        enchantmentDesc.addProperty("curse", isEnchantmentInTag(enchantment, "curse"));

        List<Enchantment> incompatibleEnchantments = registry.stream()
                .filter(other -> {
                    Holder<Enchantment> enchantmentEntry = registry.wrapAsHolder(enchantment);
                    Holder<Enchantment> otherEntry = registry.wrapAsHolder(other);
                    return !Enchantment.areCompatible(enchantmentEntry, otherEntry);
                })
                .filter(other -> other != enchantment)
                .toList();

        JsonArray excludes = new JsonArray();
        for (Enchantment excludedEnchantment : incompatibleEnchantments) {
            Identifier otherKey = registry.getKey(excludedEnchantment);
            excludes.add(otherKey.getPath());
        }
        enchantmentDesc.add("exclude", excludes);
        enchantmentDesc.addProperty("category", getEnchantmentTargetName(enchantment.definition().supportedItems()));
        enchantmentDesc.addProperty("weight", enchantment.definition().weight());
        enchantmentDesc.addProperty("tradeable", isEnchantmentInTag(enchantment, "tradeable"));
        enchantmentDesc.addProperty("discoverable", isEnchantmentInTag(enchantment, "on_random_loot"));

        return enchantmentDesc;
    }

    @Override
    public String getDataName() {
        return "enchantments";
    }

    @Override
    public JsonArray generateDataJson() {
        JsonArray resultsArray = new JsonArray();
        Registry<Enchantment> enchantmentRegistry = DGU.getWorld().registryAccess().lookupOrThrow(Registries.ENCHANTMENT);
        enchantmentRegistry.stream()
                .forEach(enchantment -> resultsArray.add(generateEnchantment(enchantmentRegistry, enchantment)));
        return resultsArray;
    }
}
